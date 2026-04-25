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
	"I return the module name from the coder if available."
	^ self coderViewModel ifNotNil: [ :vm |
		vm coderModel ifNotNil: [ :coder |
			(coder respondsTo: #contextModuleName)
				ifTrue: [ coder contextModuleName ]
				ifFalse: [
					(coder respondsTo: #moduleName)
						ifTrue: [ coder moduleName ] ] ] ]
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
	 so expand state persists across re-styles."
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
				self attribute: attr from: endPos to: endPos ] ]
]
