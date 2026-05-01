Class {
	#name : 'ElixirFunctionExpanderStyler',
	#superclass : 'GtCoderAstStyler',
	#instVars : [
		'application',
		'cachedHash',
		'cachedSites',
		'cachedAstHash',
		'cachedAst',
		'lastIndex',
		'cachedModuleAliasesFor',
		'cachedModuleAliases'
	],
	#category : 'Gt4beam',
	#package : 'Gt4beam'
}

{ #category : 'private' }
ElixirFunctionExpanderStyler >> absolutePositionForLine: line column: col in: source [
	"I convert a 1-based line:column pair to a 1-based absolute
	 character position in source."
	| lines pos |
	lines := source lines.
	line > lines size ifTrue: [ ^ nil ].
	pos := 0.
	1 to: line - 1 do: [ :i | pos := pos + (lines at: i) size + 1 ].
	^ pos + col
]

{ #category : 'accessing' }
ElixirFunctionExpanderStyler >> application [
	^ application ifNil: [
		application := BeamLinkApplication uniqueInstance ]
]

{ #category : 'accessing' }
ElixirFunctionExpanderStyler >> application: anApp [
	application := anApp
]

{ #category : 'styling' }
ElixirFunctionExpanderStyler >> attachUnknownModuleWrenchesIn: aText source: source [
	"I parse `source` locally with the SmaCC ElixirParser (the same
	 grammar `GtSmaCCParserStyler` uses for syntax highlighting),
	 walk every outermost `ElixirDotAliasNode`, and attach a wrench
	 dropdown after each one whose module isn't loaded.

	 Resolution status comes from `BeamModuleResolution` — the
	 event-driven GT-side cache.  Names already classified are
	 answered locally (zero bridge calls).  Names we've never seen
	 (`#unknown`) are batched into a single bridge call to
	 `Analysis.modules_loaded?/1`, which returns
	 `%{name => boolean()}`.  After warm-up the unknown set is
	 usually empty and we bridge zero times per source change.

	 This mirrors the Pharo styler's 'unknown class name → fix-it'
	 affordance, with the resolution check happening locally."
	| resolution ast hash allAliases nameToEndPositions unknowns query result aliasMap nameToResolved skip skipRanges |
	resolution := BeamModuleResolution default.
	"SmaCC parse is the dominant cost on big files (~1s on 5k lines).
	 Cache by source hash so the parse only runs on actual edits, not
	 on every styler invocation (cursor moves, focus changes, etc.)."
	hash := source hash.
	hash = cachedAstHash
		ifTrue: [ ast := cachedAst ]
		ifFalse: [
			ast := [ ElixirParser parseStream: source readStream ]
				on: Error do: [ nil ].
			cachedAstHash := hash.
			cachedAst := ast ].
	ast ifNil: [ ^ self ].

	"Collect every ElixirDotAliasNode, then keep only outermost —
	 nested aliases (e.g. `LocalUpload` inside `LocalUpload.Foo`) are
	 strictly contained in their wrapper and shouldn't get their own
	 wrench."
	"Collect every ElixirDotAliasNode, then keep only outermost.
	 Sort by (start asc, stop desc) and walk once tracking the
	 rightmost stop seen — O(n log n) instead of O(n²).  On a
	 ~500-line file with 2000 aliases this drops the filter from
	 ~530ms to ~5ms."
	"Collect every ElixirDotAliasNode, then drop the heads of
	 `defmodule`/`defprotocol` blocks (the module being defined,
	 not a reference) and keep only outermost spans."
	skip := self defmoduleHeadsIn: ast source: source.
	"SmaCC parses `Foo.Bar` as TWO DotAliasNodes (the full `Foo.Bar`
	 and a bare child `Foo`). Excluding the outer head from `skip`
	 isn't enough -- the bare prefix would survive, become 'outermost'
	 once its wrapper is gone, and render a wrench on the parent
	 namespace. Drop nodes whose span sits inside any head's span."
	skipRanges := skip collect: [ :h | h startPosition -> h stopPosition ].
	allAliases := OrderedCollection new.
	ast withAllNodesDo: [ :n |
		((n isKindOf: ElixirDotAliasNode)
			and: [ (skip includes: n) not
				and: [ skipRanges noneSatisfy: [ :r |
					n startPosition >= r key
						and: [ n stopPosition <= r value ] ] ] ])
			ifTrue: [ allAliases add: n ] ].
	allAliases := self outermostAliasesIn: allAliases.

	"Parse `alias` directives so locally-aliased names (e.g. `Text`
	 for `GtBridge.Phlow.Text`) classify against their resolved
	 full name instead of the short alias the source uses.

	 Grouped-alias literals (`Foo.{A, B, C}`) parse as a single
	 DotAlias node spanning the whole `Foo.{...}` text.  We can't
	 classify that literal -- it's not a single module name -- so
	 expand it into per-name entries via `groupedAliasEntriesFor:in:`
	 (which reuses the same parser as `extractAliasesFrom:`).  Each
	 inner name gets its own wrench position; non-grouped DotAlias
	 nodes go through the alias map as before."
	aliasMap := self extractAliasesFrom: source.
	"In the inline function editor (the |> expander, the Meta
	 browser's Functions tab) the editor's source is the function
	 body in isolation -- the surrounding `defmodule`'s `alias`
	 lines aren't part of `source`.  Without them, bare references
	 like `ColumnedList` resolve to themselves and get a wrench
	 even though the enclosing module aliases them.  Merge in the
	 context module's aliases via `Analysis.module_aliases/1`,
	 cached per-styler so we don't bridge on every keystroke.
	 Source-extracted aliases win on conflict (the user's local
	 `alias` line takes precedence over a stale module-level one)."
	self contextModuleName ifNotNil: [ :mod |
		(self moduleAliasesFor: mod) do: [ :pair |
			aliasMap at: pair first ifAbsentPut: [ pair second ] ] ].
	nameToEndPositions := Dictionary new.
	nameToResolved := Dictionary new.
	allAliases do: [ :n |
		| nodeSrc |
		nodeSrc := source copyFrom: n startPosition to: n stopPosition.
		(nodeSrc includes: ${)
			ifTrue: [
				(self groupedAliasEntriesFor: n in: source) do: [ :assoc |
					| name endPos |
					name := assoc key.
					endPos := assoc value.
					(nameToEndPositions at: name ifAbsentPut: [ OrderedCollection new ])
						add: endPos.
					nameToResolved at: name put: name ] ]
			ifFalse: [
				| name resolved |
				name := nodeSrc.
				resolved := self resolveAlias: name with: aliasMap.
				(nameToEndPositions at: name ifAbsentPut: [ OrderedCollection new ])
					add: n stopPosition.
				nameToResolved at: name put: resolved ] ].

	"Classify locally on the RESOLVED names; collect unknowns for one batch query."
	unknowns := (nameToResolved values asSet) select: [ :resolved |
		(resolution classify: resolved) = #unknown ].

	"One bridge call carrying just the unknown names (typically a
	 small list of strings, kilobytes vs. the whole source).  After
	 warm-up `unknowns` is usually empty and we don't bridge at all."
	unknowns isNotEmpty ifTrue: [
		| listExpr res resolvedNames unresolvedNames |
		listExpr := String streamContents: [ :s |
			s nextPutAll: '['.
			unknowns asArray
				do: [ :n | s nextPut: $"; nextPutAll: n; nextPut: $" ]
				separatedBy: [ s nextPutAll: ', ' ].
			s nextPutAll: ']' ].
		query := 'GtBridge.Analysis.modules_loaded?(', listExpr, ')'.
		res := [ self application evaluateAndWait: query ]
			on: Error do: [ nil ].
		res ifNotNil: [
			resolvedNames := OrderedCollection new.
			unresolvedNames := OrderedCollection new.
			unknowns do: [ :name |
				| loaded |
				loaded := [ res attributeAt: name ]
					on: Error do: [ nil ].
				loaded == true ifTrue: [ resolvedNames add: name ].
				loaded == false ifTrue: [ unresolvedNames add: name ] ].
			resolution recordResolved: resolvedNames unresolved: unresolvedNames ] ].

	"Attach wrench at every span whose RESOLVED name is unresolved.
	 The wrench attribute carries the resolved name, so 'Create
	 module' creates the canonical full name not the alias.  For
	 grouped-alias literals each inner name contributes its own
	 end position; non-grouped names contribute one position per
	 occurrence."
	nameToEndPositions keysAndValuesDo: [ :name :positions |
		| resolved |
		resolved := nameToResolved at: name.
		(resolution classify: resolved) = #unresolved ifTrue: [
			positions do: [ :endPos |
				endPos <= aText size ifTrue: [
					| attr |
					attr := ElixirUnknownModuleAttribute
						forModule: resolved
						application: self application.
					self attribute: attr from: endPos to: endPos ] ] ] ]
]

{ #category : 'accessing' }
ElixirFunctionExpanderStyler >> contextModuleName [
	"I return the module name from the coder. Every Elixir coder that
	 attaches me — GtElixirCoderModel, ElixirModuleCoder,
	 ElixirFunctionCoder — implements #contextModuleName."
	^ self coderViewModel ifNotNil: [ :vm |
		vm coderModel ifNotNil: [ :coder | coder contextModuleName ] ]
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> defmoduleHeadsIn: ast source: source [
	"I return an IdentitySet of `ElixirDotAliasNode` instances that
	 are the first argument of `defmodule X do ... end` or
	 `defprotocol X do ... end` — the module being *defined*, not a
	 reference.  The wrench should never appear on these (creating
	 a file for a module that's defined right here would conflict).

	 Mirrors the BEAM-side `Walker.collect_module_refs/2`'s
	 defmodule/defprotocol skip clause."
	| skip |
	skip := IdentitySet new.
	ast withAllNodesDo: [ :node |
		(node isKindOf: ElixirBlockExprNode) ifTrue: [
			| identSrc |
			identSrc := [ source
				copyFrom: node identifier startPosition
				to: node identifier stopPosition ]
				on: Error do: [ '' ].
			(#('defmodule' 'defprotocol') includes: identSrc) ifTrue: [
				[ skip add: node call expressions first ]
					on: Error do: [  ] ] ] ].
	^ skip
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> extractAliasesFrom: source [
	"I parse `alias` directives line-by-line and return a Dictionary
	 mapping the short name to the fully qualified module name.

	 Three forms:
	   alias Foo.Bar.Baz             ->  Baz -> Foo.Bar.Baz
	   alias Foo.Bar.Baz, as: Z      ->  Z   -> Foo.Bar.Baz
	   alias Foo.Bar.{X, Y, Z}       ->  X   -> Foo.Bar.X
	                                     Y   -> Foo.Bar.Y
	                                     Z   -> Foo.Bar.Z

	 Without me, every locally-aliased identifier (e.g. `Text` for
	 `GtBridge.Phlow.Text`) shows up as an unresolved module and the
	 styler attaches a wrench.  With me, the styler classifies the
	 RESOLVED full name instead, so the wrench only fires when the
	 module truly isn't loaded."
	| aliases |
	aliases := Dictionary new.
	source lines do: [ :rawLine |
		| line body |
		line := rawLine trimBoth.
		(line beginsWith: 'alias ') ifTrue: [
			body := (line copyFrom: 7 to: line size) trimBoth.
			(body includes: ${)
				ifTrue: [ self parseGroupedAlias: body into: aliases ]
				ifFalse: [ self parseSingleAlias: body into: aliases ] ] ].
	^ aliases
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> groupedAliasEntriesFor: aNode in: source [
	"I expand a grouped-alias DotAlias node (whose source span is
	 `Foo.{A, B, C}`) into per-name entries suitable for wrench
	 attachment.  Returns OrderedCollection of associations
	 `fullModuleName -> absoluteEndPositionInSource`, one per
	 individual name inside the braces.

	 Without me, the AST walker treats the whole `Foo.{A, B, C}`
	 literal as a single module reference and offers to create that
	 verbatim string -- which isn't a real module.  With me, each
	 name resolves to its canonical full form (`Foo.A`, `Foo.B`,
	 `Foo.C`) and gets its own wrench."
	| absStart nodeSrc |
	absStart := aNode startPosition.
	nodeSrc := source copyFrom: aNode startPosition to: aNode stopPosition.
	^ (self parseGroupedAliasBody: nodeSrc) collect: [ :assoc |
		assoc key -> (absStart + assoc value - 1) ]
]

{ #category : 'initialization' }
ElixirFunctionExpanderStyler >> initialize [
	super initialize.
	lastIndex := 0
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> moduleAliasesFor: aModuleName [
	"I return the surrounding module's `alias` declarations as an
	 `OrderedCollection` of `{short. full}` pairs.  Bridge-cached
	 per styler instance, keyed on the module name -- module aliases
	 rarely change, and the styler runs on every keystroke.

	 Returns empty on bridge error or if the module has no aliases."
	cachedModuleAliasesFor = aModuleName ifTrue: [ ^ cachedModuleAliases ].
	cachedModuleAliasesFor := aModuleName.
	cachedModuleAliases := [
		(self application evaluateAndWait:
			'GtBridge.Analysis.module_aliases(', aModuleName, ')')
				asList collect: [ :proxyPair |
					| items |
					items := proxyPair asList.
					{ items first asString. items second asString } ] ]
		on: Error do: [ #() ].
	^ cachedModuleAliases
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> nextIndex [
	^ lastIndex := lastIndex + 1
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> outermostAliasesIn: aCollection [
	"I return the outermost ElixirDotAliasNodes from `aCollection`,
	 dropping every node whose span is strictly contained in
	 another.  Sort + single-pass O(n log n) — DotAliasNodes don't
	 overlap (only nest or are disjoint), so once the current
	 outermost ends, any later node with start > its stop is the
	 next outermost."
	| sorted outermost outerStop |
	sorted := aCollection asSortedCollection: [ :a :b |
		a startPosition < b startPosition
			or: [ a startPosition = b startPosition
				and: [ a stopPosition > b stopPosition ] ] ].
	outermost := OrderedCollection new.
	outerStop := 0.
	sorted do: [ :node |
		node startPosition > outerStop ifTrue: [
			outermost add: node.
			outerStop := node stopPosition ] ].
	^ outermost
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> parseGroupedAlias: body into: aliases [
	"I parse `Foo.Bar.{A, B, C}` and emit per-name entries."
	(self parseGroupedAliasBody: body) do: [ :assoc |
		| full short |
		full := assoc key.
		short := (full substrings: '.') last.
		aliases at: short put: full ]
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> parseGroupedAliasBody: body [
	"I parse a grouped alias body of the form `Foo.Bar.{A, B, C}`
	 and return an OrderedCollection of associations
	 `fullName -> endPositionInBody`, where the end position is the
	 1-based index of the LAST character of each short name within
	 `body`.  Returns an empty collection if the body is malformed
	 or has no prefix.

	 Both the alias-map extractor (which discards positions) and the
	 grouped-wrench expander (which needs them to attach wrenches at
	 each individual name) go through me."
	| openIdx closeIdx prefix result nameStart i ch endRel name |
	openIdx := body indexOf: ${.
	closeIdx := body indexOf: $} startingAt: openIdx.
	(openIdx > 1 and: [ closeIdx > openIdx ]) ifFalse: [ ^ #() ].
	prefix := (body copyFrom: 1 to: openIdx - 2) trimBoth.
	prefix isEmpty ifTrue: [ ^ #() ].
	result := OrderedCollection new.
	nameStart := nil.
	i := openIdx + 1.
	[ i <= closeIdx ] whileTrue: [
		ch := body at: i.
		(ch = $, or: [ ch = $} ])
			ifTrue: [
				nameStart ifNotNil: [
					name := (body copyFrom: nameStart to: i - 1) trimBoth.
					name isEmpty ifFalse: [
						endRel := i - 1.
						[ endRel >= nameStart and: [ (body at: endRel) isSeparator ] ]
							whileTrue: [ endRel := endRel - 1 ].
						result add: prefix , '.' , name -> endRel ] ].
				nameStart := nil ]
			ifFalse: [
				ch isSeparator ifFalse: [
					nameStart ifNil: [ nameStart := i ] ] ].
		i := i + 1 ].
	^ result
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> parseSingleAlias: body into: aliases [
	"I parse `Foo.Bar.Baz` (short defaults to last segment) and
	 `Foo.Bar.Baz, as: Z` (short = Z) forms."
	| asIdx |
	asIdx := body indexOfSubCollection: ', as: '.
	asIdx > 0
		ifTrue: [
			| full short |
			full := (body copyFrom: 1 to: asIdx - 1) trimBoth.
			short := (body copyFrom: asIdx + 6 to: body size) trimBoth.
			(full isEmpty or: [ short isEmpty ]) ifFalse: [
				aliases at: short put: full ] ]
		ifFalse: [
			| full short |
			full := body trimBoth.
			(full isEmpty or: [ full includes: $  ]) ifFalse: [
				short := (full substrings: '.') last.
				aliases at: short put: full ] ]
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> resolveAlias: aName with: anAliasMap [
	"I expand `aName` through the alias map.  If the head segment
	 (before the first dot) is a key in the map, replace it with the
	 mapped full name.  Otherwise return `aName` unchanged.

	 Examples (with map { 'Text' -> 'GtBridge.Phlow.Text' }):
	   'Text'            ->  'GtBridge.Phlow.Text'
	   'Text.Inner'      ->  'GtBridge.Phlow.Text.Inner'
	   'NotAnAlias.Foo'  ->  'NotAnAlias.Foo'  (unchanged)"
	| segments head tail resolved |
	segments := aName substrings: '.'.
	head := segments first.
	resolved := anAliasMap at: head ifAbsent: [ ^ aName ].
	tail := segments allButFirst.
	tail isEmpty ifTrue: [ ^ resolved ].
	^ String streamContents: [ :s |
		s nextPutAll: resolved.
		tail do: [ :seg | s nextPut: $.; nextPutAll: seg ] ]
]

{ #category : 'styling' }
ElixirFunctionExpanderStyler >> style: aText ast: theAst [
	"I query the BEAM for resolvable call sites and attach expander
	 triangles using GT's expander framework. Each gets a unique ID
	 (resetting lastIndex per cycle) so expand state persists across
	 re-styles.

	 Two-tier cache: cachedHash/cachedSites short-circuits the BEAM
	 round-trip for back-to-back styles of the same source. On miss
	 the BEAM-side :gtbridge_cache (keyed
	 {:call_sites, contextModule, sourceHash}) serves cross-coder
	 hits lock-free and is invalidated by CacheReaper when modules
	 recompile via the EventBroker bus."
	| source hash sites b64 query |
	text := aText.
	lastIndex := 0.
	source := aText asString.
	source size < 10 ifTrue: [ ^ self ].
	hash := source hash.
	hash = cachedHash
		ifTrue: [ sites := cachedSites ]
		ifFalse: [
			b64 := ZnBase64Encoder new encode: source utf8Encoded.
			query := 'GtBridge.Analysis.call_sites(Base.decode64!("', b64, '")'.
			self contextModuleName ifNotNil: [ :mod |
				query := query, ', ', mod ].
			query := query, ')'.
			sites := [ (self application evaluateAndWait: query) asList ]
				on: Error do: [ #() ].
			cachedHash := hash.
			cachedSites := sites ].
	sites do: [ :site |
		| line col fnName absPos |
		line := (site attributeAt: #line) asInteger.
		col := (site attributeAt: #column) asInteger.
		fnName := (site attributeAt: #function) asString.
		absPos := self absolutePositionForLine: line column: col in: source.
		(absPos isNotNil and: [ absPos + fnName size - 1 <= aText size ])
			ifTrue: [
				| endPos attr |
				endPos := absPos + fnName size - 1.
				attr := ElixirFunctionExpanderAttribute new
					targetModule: (site attributeAt: #target_module) asString
					functionName: fnName
					arity: (site attributeAt: #arity) asInteger
					application: self application.
				attr id: ('elixir-expander--', self nextIndex asString) asSymbol.
				self attribute: attr from: endPos to: endPos ] ].

	self attachUnknownModuleWrenchesIn: aText source: source
]
