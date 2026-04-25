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
	header := BrHorizontalPane new
		hFitContent;
		vFitContent;
		constraintsDo: [ :c |
			c ignoreByLayout.
			c ignored horizontal alignLeft.
			c ignored vertical alignTop.
			c margin: (BlInsets top: 2 left: 8 bottom: 0 right: 8) ];
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
	"I rebuild the Module > function/arity header from the bound
	 coder. Each label has its own click handler — module spawns
	 module docs, function spawns function docs."
	| coder moduleName functionName arity application |
	coder := self textualCoderViewModel coder.
	moduleName := coder moduleCoder ifNotNil: [ :mc | mc moduleName ] ifNil: [ '?' ].
	functionName := coder functionName.
	arity := coder arity.
	application := coder moduleCoder ifNotNil: [ :mc | mc application ].
	header removeChildren.
	header addChild: (BrLabel new
		aptitude: (BrGlamorousLabelAptitude new
			foreground: (Color fromHexString: '666666'); fontSize: 11);
		text: moduleName;
		addEventHandlerOn: BlClickEvent do: [ :evt |
			evt consumed: true.
			application ifNotNil: [
				evt currentTarget phlow spawnObject:
					(application evaluateAndWait:
						'GtBridge.Documentation.for_module(', moduleName, ')') ] ];
		yourself).
	header addChild: (BrLabel new
		aptitude: (BrGlamorousLabelAptitude new
			foreground: (Color fromHexString: '999999'); fontSize: 11);
		text: ' > ';
		margin: (BlInsets left: 4 right: 4);
		yourself).
	header addChild: (BrLabel new
		aptitude: (BrGlamorousLabelAptitude new bold; fontSize: 11);
		text: functionName, '/', arity asString;
		addEventHandlerOn: BlClickEvent do: [ :evt |
			evt consumed: true.
			application ifNotNil: [
				evt currentTarget phlow spawnObject:
					(application evaluateAndWait:
						'GtBridge.Documentation.for_function(', moduleName,
							', :', functionName, ', ', arity asString, ')') ] ];
		yourself)
]
