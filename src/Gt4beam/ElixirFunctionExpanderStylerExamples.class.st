Class {
	#name : 'ElixirFunctionExpanderStylerExamples',
	#superclass : 'Object',
	#category : 'Gt4beam-Examples',
	#package : 'Gt4beam',
	#tag : 'Examples'
}

{ #category : 'examples' }
ElixirFunctionExpanderStylerExamples >> queryAloneKeepsTheShortForm [
	"No page context, no context module: the query stays the arity-1 call."

	<gtExample>
	| query |
	query := ElixirFunctionExpanderStyler
		callSitesQueryFor: 'Enum.sum([1])'
		context: nil
		siblings: #(  ).
	self
		assert: query
		equals: 'GtBridge.Analysis.call_sites(Base.decode64!("'
			, (ZnBase64Encoder new encode: 'Enum.sum([1])' utf8Encoded) , '"))'.
	^ query
]

{ #category : 'examples' }
ElixirFunctionExpanderStylerExamples >> queryPutsTheContextModuleSecond [
	"A context module rides in argument two as a bare module literal."

	<gtExample>
	| query |
	query := ElixirFunctionExpanderStyler
		callSitesQueryFor: 'Enum.sum([1])'
		context: 'Foo.Bar'
		siblings: #(  ).
	self
		assert: query
		equals: 'GtBridge.Analysis.call_sites(Base.decode64!("'
			, (ZnBase64Encoder new encode: 'Enum.sum([1])' utf8Encoded) , '"), Foo.Bar)'.
	^ query
]

{ #category : 'examples' }
ElixirFunctionExpanderStylerExamples >> queryShipsSiblingsAsSeparateArguments [
	"Siblings travel as independently decoded strings, with an explicit
	 nil context holding the second position."

	<gtExample>
	| query enc |
	enc := [ :s | 'Base.decode64!("' , (ZnBase64Encoder new encode: s utf8Encoded) , '")' ].
	query := ElixirFunctionExpanderStyler
		callSitesQueryFor: 'Enum.sum([1])'
		context: nil
		siblings: #( 'alias A.B' 'broken(' ).
	self
		assert: query
		equals: 'GtBridge.Analysis.call_sites(' , (enc value: 'Enum.sum([1])')
			, ', nil, [' , (enc value: 'alias A.B') , ', ' , (enc value: 'broken(') , '])'.
	^ query
]
