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
	#category : 'Gt4beam-Styler',
	#package : 'Gt4beam',
	#tag : 'Styler'
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

{ #category : 'private' }
ElixirFunctionExpanderStyler >> aliasMapFor: source [
	"Source-level `alias` directives, the surrounding page's sibling
	 aliases (when running inside a Lepiter snippet), and the
	 surrounding module's aliases (when a context module is known).
	 Precedence: source > page > module — the closer-to-the-cursor
	 declaration wins."
	| aliasMap |
	aliasMap := self extractAliasesFrom: source.
	self pageAliasSource ifNotNil: [ :pageSrc |
		(self extractAliasesFrom: pageSrc) keysAndValuesDo: [ :k :v |
			aliasMap at: k ifAbsentPut: [ v ] ] ].
	self contextModuleName ifNotNil: [ :mod |
		(self moduleAliasesFor: mod) do: [ :pair |
			aliasMap at: pair first ifAbsentPut: [ pair second ] ] ].
	^ aliasMap
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
	"I attach a wrench dropdown after every Elixir module reference
	 whose module isn't loaded."
	| resolution ast aliases entries |
	ast := self parsedAstFor: source.
	ast ifNil: [ ^ self ].
	resolution := BeamModuleResolution default.
	aliases := self outermostAliasReferencesIn: ast source: source.
	entries := self wrenchEntriesFor: aliases source: source.
	self learnClassificationsFor: (entries collect: [ :e | e key value ]) asSet on: resolution.
	entries do: [ :entry |
		self attachWrenchEntry: entry in: aText resolution: resolution ]
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> attachWrenchEntry: entry in: aText resolution: resolution [
	"Attach a wrench attribute at the entry's end position iff its
	 resolved name is known-unresolved by the cache."
	| resolved endPos attr |
	resolved := entry key value.
	endPos := entry value.
	(resolution classify: resolved) = #unresolved ifFalse: [ ^ self ].
	endPos > aText size ifTrue: [ ^ self ].
	attr := ElixirUnknownModuleAttribute
		forModule: resolved
		application: self application.
	self attribute: attr from: endPos to: endPos
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> attachedCoder [
	"I return the coderModel my view model wraps, or nil if I'm not
	 yet attached."
	^ self coderViewModel ifNotNil: [ :vm | vm coderModel ]
]

{ #category : 'accessing' }
ElixirFunctionExpanderStyler >> contextModuleName [
	"Every Elixir coder I attach to — GtElixirCoderModel,
	 ElixirModuleCoder, ElixirFunctionCoder — implements
	 #contextModuleName."
	^ self attachedCoder ifNotNil: [ :coder | coder contextModuleName ]
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> defmoduleHeadsIn: ast source: source [
	"I return DotAliasNodes that are the head of a `defmodule` /
	 `defprotocol` block — the module being defined, not a reference."
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
	 short-name → full-module-name.  Three forms:
	   alias Foo.Bar.Baz             ->  Baz -> Foo.Bar.Baz
	   alias Foo.Bar.Baz, as: Z      ->  Z   -> Foo.Bar.Baz
	   alias Foo.Bar.{X, Y, Z}       ->  X   -> Foo.Bar.X
	                                     Y   -> Foo.Bar.Y
	                                     Z   -> Foo.Bar.Z"
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
	"I expand a grouped-alias node (`Foo.{A, B, C}`) into per-name
	 associations `fullName -> absoluteEndPosition`, one per inner name."
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
ElixirFunctionExpanderStyler >> learnClassificationsFor: resolvedNames on: resolution [
	"Batch-classify any `resolvedNames` the cache hasn't seen via one
	 bridge call; record each as resolved/unresolved so subsequent
	 `classify:` calls answer locally."
	| unknowns res resolved unresolved |
	unknowns := resolvedNames select: [ :n |
		(resolution classify: n) = #unknown ].
	unknowns isEmpty ifTrue: [ ^ self ].
	res := [ self application evaluateAndWait:
		'GtBridge.Analysis.modules_loaded?(', (self listExprFor: unknowns), ')' ]
		on: Error do: [ ^ self ].
	res ifNil: [ ^ self ].
	resolved := OrderedCollection new.
	unresolved := OrderedCollection new.
	unknowns do: [ :name |
		| loaded |
		loaded := [ res attributeAt: name ] on: Error do: [ nil ].
		loaded == true ifTrue: [ resolved add: name ].
		loaded == false ifTrue: [ unresolved add: name ] ].
	resolution recordResolved: resolved unresolved: unresolved
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> listExprFor: names [
	"Render `names` as an Elixir list literal of double-quoted strings."
	^ String streamContents: [ :s |
		s nextPutAll: '['.
		names asArray
			do: [ :n | s nextPut: $"; nextPutAll: n; nextPut: $" ]
			separatedBy: [ s nextPutAll: ', ' ].
		s nextPutAll: ']' ]
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> moduleAliasesFor: aModuleName [
	"I return `{short. full}` pairs for the module's `alias` lines.
	 Cached per styler instance — module aliases rarely change and
	 the styler runs on every keystroke."
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
ElixirFunctionExpanderStyler >> outermostAliasReferencesIn: ast source: source [
	"DotAliasNode references in `source`, minus the defmodule head and
	 any bare children inside it.  SmaCC parses `Foo.Bar` as outer +
	 bare-child `Foo`; skipping only the head would leave the prefix
	 'outermost' and wrench the parent namespace, so drop entire spans
	 inside any head."
	| skip skipRanges all |
	skip := self defmoduleHeadsIn: ast source: source.
	skipRanges := skip collect: [ :h | h startPosition -> h stopPosition ].
	all := OrderedCollection new.
	ast withAllNodesDo: [ :n |
		((n isKindOf: ElixirDotAliasNode)
			and: [ (skip includes: n) not
				and: [ skipRanges noneSatisfy: [ :r |
					n startPosition >= r key
						and: [ n stopPosition <= r value ] ] ] ])
			ifTrue: [ all add: n ] ].
	^ self outermostAliasesIn: all
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> outermostAliasesIn: aCollection [
	"I drop nodes whose span is strictly contained in another.
	 Sort + single-pass O(n log n)."
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

{ #category : 'accessing' }
ElixirFunctionExpanderStyler >> pageAliasSource [
	"Extra Elixir source whose `alias`/`import` lines should also
	 resolve here — Lepiter snippet elements populate it with their
	 sibling snippets' aliases.  Non-Lepiter coders return nil."
	^ self attachedCoder ifNotNil: [ :coder | coder pageAliasSource ]
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
	"I parse `Foo.Bar.{A, B, C}` into associations
	 `fullName -> 1-based-end-index-in-body`, one per inner name."
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
ElixirFunctionExpanderStyler >> parsedAstFor: source [
	"Cached SmaCC parse of `source`.  Cache key is the source hash so
	 back-to-back styles of the same buffer don't reparse."
	| hash |
	hash := source hash.
	hash = cachedAstHash ifTrue: [ ^ cachedAst ].
	cachedAst := [ ElixirParser parseStream: source readStream ]
		on: Error do: [ nil ].
	cachedAstHash := hash.
	^ cachedAst
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> resolveAlias: aName with: anAliasMap [
	"I replace `aName`'s head segment via the alias map.  Examples
	 with `{ 'Text' -> 'GtBridge.Phlow.Text' }`:
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
	"I attach expander triangles at every resolvable call site.
	 Each gets a unique ID (resetting lastIndex per cycle) so expand
	 state persists across re-styles.  cachedHash/cachedSites
	 short-circuits the BEAM round-trip for back-to-back styles of
	 the same source.

	 Sites arrive as a JSON relation of values, not proxies: I read
	 every field of every site, and a proxy field read is a bridge
	 round trip.

	 A bridge error (an older gt_bridge without call_sites_relation,
	 say) yields no triangles for this pass and is deliberately not
	 cached, so the next restyle retries instead of staying blank
	 until the source changes."
	| source effectiveSource pageSrc hash sites reply b64 query |
	text := aText.
	lastIndex := 0.
	source := aText asString.
	source size < 10 ifTrue: [ ^ self ].
	pageSrc := self pageAliasSource ifNil: [ '' ].
	"Append page-level aliases after the original source so BEAM's
	 extract_alias_map picks them up.  The parser scans the whole
	 string for `alias` lines regardless of position, and call-site
	 line/col come from the real-code section, so appending doesn't
	 shift any in-editor positions."
	effectiveSource := pageSrc isEmpty
		ifTrue: [ source ]
		ifFalse: [ source , String lf , pageSrc ].
	hash := { source hash. self contextModuleName. pageSrc hash }.
	hash = cachedHash
		ifTrue: [ sites := cachedSites ]
		ifFalse: [
			b64 := ZnBase64Encoder new encode: effectiveSource utf8Encoded.
			query := 'GtBridge.Analysis.call_sites_relation(Base.decode64!("', b64, '")'.
			self contextModuleName ifNotNil: [ :mod |
				query := query, ', ', mod ].
			query := query, ')'.
			reply := self application evaluateAndWait: query.
			(reply isKindOf: BeamBridgeEvalError)
				ifTrue: [ sites := #() ]
				ifFalse: [
					sites := STONJSON fromString: reply asString.
					cachedHash := hash.
					cachedSites := sites ] ].
	sites do: [ :site |
		| line col fnName absPos |
		line := site at: 'line'.
		col := site at: 'column'.
		fnName := site at: 'function'.
		absPos := self absolutePositionForLine: line column: col in: source.
		(absPos isNotNil and: [ absPos + fnName size - 1 <= aText size ])
			ifTrue: [
				| endPos attr |
				endPos := absPos + fnName size - 1.
				attr := ElixirFunctionExpanderAttribute new
					targetModule: (site at: 'target_module')
					functionName: fnName
					arity: (site at: 'arity')
					application: self application.
				attr id: ('elixir-expander--', self nextIndex asString) asSymbol.
				self attribute: attr from: endPos to: endPos ] ].

	self attachUnknownModuleWrenchesIn: aText source: source
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> wrenchEntriesFor: aliasNodes source: source [
	"For each alias node, emit `(name -> resolved) -> endPosition`.
	 Inline function editors show a body without the enclosing `alias`
	 lines, so merge the context module's aliases into the local map
	 before resolving.  Grouped `Foo.{A, B}` literals expand to one
	 entry per inner name."
	| aliasMap entries |
	aliasMap := self aliasMapFor: source.
	entries := OrderedCollection new.
	aliasNodes do: [ :n |
		| nodeSrc |
		nodeSrc := source copyFrom: n startPosition to: n stopPosition.
		(nodeSrc includes: ${)
			ifTrue: [
				(self groupedAliasEntriesFor: n in: source) do: [ :assoc |
					entries add: (assoc key -> assoc key) -> assoc value ] ]
			ifFalse: [
				entries add: (nodeSrc -> (self resolveAlias: nodeSrc with: aliasMap))
					-> n stopPosition ] ].
	^ entries
]
