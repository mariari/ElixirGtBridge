Class {
	#name : 'ElixirFunctionExpanderStyler',
	#superclass : 'GtCoderAstStyler',
	#instVars : [
		'application',
		'cachedHash',
		'cachedSites',
		'lastIndex'
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

{ #category : 'accessing' }
ElixirFunctionExpanderStyler >> contextModuleName [
	"I return the module name from the coder. Every Elixir coder that
	 attaches me — GtElixirCoderModel, ElixirModuleCoder,
	 ElixirFunctionCoder — implements #contextModuleName."
	^ self coderViewModel ifNotNil: [ :vm |
		vm coderModel ifNotNil: [ :coder | coder contextModuleName ] ]
]

{ #category : 'initialization' }
ElixirFunctionExpanderStyler >> initialize [
	super initialize.
	lastIndex := 0
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> nextIndex [
	^ lastIndex := lastIndex + 1
]

{ #category : 'styling' }
ElixirFunctionExpanderStyler >> style: aText ast: theAst [
	"I query the BEAM for resolvable call sites and attach expander
	 triangles using GT's expander framework. Each gets a unique ID
	 (resetting lastIndex per cycle) so expand state persists across
	 re-styles.

	 Sites arrive as a JSON relation of values, not proxies: I read
	 every field of every site, and a proxy field read is a bridge
	 round trip.

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
			query := 'GtBridge.Analysis.call_sites_relation(Base.decode64!("', b64, '")'.
			self contextModuleName ifNotNil: [ :mod |
				query := query, ', ', mod ].
			query := query, ')'.
			sites := [ STONJSON fromString:
					(self application evaluateAndWait: query) asString ]
				on: Error do: [ #() ].
			cachedHash := hash.
			cachedSites := sites ].
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
				self attribute: attr from: endPos to: endPos ] ]
]
