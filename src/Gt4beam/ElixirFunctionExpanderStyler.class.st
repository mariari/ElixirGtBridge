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
	"I attach a wrench dropdown after every Elixir module reference
	 whose module isn't loaded."
	| resolution ast hash allAliases nameToEndPositions unknowns query
	  aliasMap nameToResolved skip skipRanges |
	resolution := BeamModuleResolution default.
	hash := source hash.
	hash = cachedAstHash
		ifTrue: [ ast := cachedAst ]
		ifFalse: [
			ast := [ ElixirParser parseStream: source readStream ]
				on: Error do: [ nil ].
			cachedAstHash := hash.
			cachedAst := ast ].
	ast ifNil: [ ^ self ].

	"SmaCC parses `Foo.Bar` as outer + bare-child `Foo`.  Skipping
	 only the head leaves the bare prefix as 'outermost' and would
	 wrench the parent namespace; drop spans inside any head."
	skip := self defmoduleHeadsIn: ast source: source.
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

	"Inline function editors show a function body without the
	 enclosing `alias` lines; merge the module's aliases so bare
	 references classify against the right full name."
	aliasMap := self extractAliasesFrom: source.
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
				"`Foo.{A, B, C}` is one DotAlias node; expand to per-name
				 entries so each inner name gets its own wrench position."
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

	unknowns := (nameToResolved values asSet) select: [ :resolved |
		(resolution classify: resolved) = #unknown ].
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
	 the same source."
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
