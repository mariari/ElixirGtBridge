Class {
	#name : 'ElixirFilterFunctionCoderElement',
	#superclass : 'GtExpandableSourceCoderElement',
	#instVars : [
		'header'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'initialization' }
ElixirFilterFunctionCoderElement >> initialize [
	super initialize.
	"Reserve a thin row at top for the overlaid header."
	self padding: (BlInsets top: 18 left: 0 bottom: 0 right: 0).
	header := BrHorizontalPane new
		hMatchParent;
		vFitContent;
		constraintsDo: [ :c |
			c ignoreByLayout.
			c ignored horizontal alignLeft.
			c ignored vertical alignTop ];
		zIndex: 10;
		yourself.
	self addChild: header
]

{ #category : 'hooks' }
ElixirFilterFunctionCoderElement >> onPostTextualCoderViewModelChanged [
	super onPostTextualCoderViewModelChanged.
	self populateHeaderFromCoder
]

{ #category : 'accessing' }
ElixirFilterFunctionCoderElement >> populateHeaderFromCoder [
	"I rebuild the header from the bound coder using the same
	 builder the |> expander uses, so look and behavior match."
	| coder moduleName |
	coder := self textualCoderViewModel coder.
	moduleName := coder moduleCoder ifNotNil: [ :mc | mc moduleName ] ifNil: [ '?' ].
	header removeChildren.
	header addChild: (ElixirFunctionExpanderAttribute
		buildHeaderForModule: moduleName
		functionName: coder functionName
		arity: coder arity
		application: (coder moduleCoder ifNotNil: [ :mc | mc application ]))
]
