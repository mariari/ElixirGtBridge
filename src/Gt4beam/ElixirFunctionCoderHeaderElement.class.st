Class {
	#name : 'ElixirFunctionCoderHeaderElement',
	#superclass : 'BrHorizontalPane',
	#traits : 'TGtWithTextualCoderViewModel',
	#classTraits : 'TGtWithTextualCoderViewModel classTrait',
	#instVars : [
		'textualCoderViewModel'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'instance creation' }
ElixirFunctionCoderHeaderElement class >> forModule: aModuleName functionName: aFunctionName arity: anArity application: anApplication [
	"I return a ready-to-use breadcrumb pane for callers that don't
	 have a textualCoderViewModel to bind (e.g. ElixirFunctionExpanderAttribute's
	 inline expansion of |> calls). The instance form populates from
	 a bound coder; this form populates directly."
	^ self new
		populateForModule: aModuleName
		functionName: aFunctionName
		arity: anArity
		application: anApplication;
		yourself
]

{ #category : 'private' }
ElixirFunctionCoderHeaderElement >> buildBreadcrumb [
	| coder |
	coder := textualCoderViewModel coder.
	coder moduleCoder ifNil: [ ^ #() ].
	^ self
		buildButtonsForModule: coder moduleCoder moduleName
		functionName: coder functionName
		arity: coder arity
		application: coder moduleCoder application
]

{ #category : 'private' }
ElixirFunctionCoderHeaderElement >> buildButtonsForModule: aModuleName functionName: aFunctionName arity: anArity application: anApplication [
	"Shared between the bound-view-model path (filter rows) and the
	 direct path (|> expander). Module + > + function/arity buttons."
	^ {
		self
			newButton: aModuleName
			action: [
				anApplication ifNotNil: [ :a |
					self phlow spawnObject:
						(a evaluateAndWait:
							'GtBridge.Documentation.for_module(', aModuleName, ')') ] ].
		self newSeparator.
		self
			newButton: aFunctionName , '/' , anArity asString
			action: [
				anApplication ifNotNil: [ :a |
					self phlow spawnObject:
						(a evaluateAndWait:
							'GtBridge.Documentation.for_function(', aModuleName,
								', :', aFunctionName, ', ',
								anArity asString, ')') ] ] }
]

{ #category : 'initialization' }
ElixirFunctionCoderHeaderElement >> initialize [
	"Modeled on GtPharoMethodCoderHeaderElement: a horizontal
	 pane with breadcrumb buttons. Children are populated when
	 textualCoderViewModel: is set, since module/function come
	 from the bound coder."
	super initialize.
	self
		fitContent;
		alignCenterLeft
]

{ #category : 'private' }
ElixirFunctionCoderHeaderElement >> newButton: aText action: aBlock [
	"Mirror GtPharoMethodCoderHeaderElement>>newPackageButton:
	 metadata-label aptitude (looks like inline text), with a
	 subtle border on hover for affordance. BrButton handles the
	 click event itself, which is the whole point of switching
	 from BrLabel + addEventFilterOn:."
	^ BrButton new
		fitContent;
		beSmallSize;
		aptitude: BrGlamorousMetadataLabelAptitude new
				+ (BrStyleCommonAptitude new
					default: [ :aStyle |
						aStyle
							geometry: (BlRoundedRectangleGeometry cornerRadius: 4);
							border: BlBorder empty ];
					hovered: [ :aStyle |
						aStyle border: self theme button hoveredBorderColor ]);
		label: aText;
		action: aBlock
]

{ #category : 'private' }
ElixirFunctionCoderHeaderElement >> newSeparator [
	^ BrLabel new
		aptitude: (BrGlamorousLabelAptitude new thin
			padding: (BlInsets all: 0);
			foreground: self theme label metadataTextForeground);
		text: '>';
		margin: (BlInsets left: 5 right: 5)
]

{ #category : 'updating' }
ElixirFunctionCoderHeaderElement >> onTextualCoderViewModelChanged [
	"GT framework calls textualCoderViewModel: on me after I'm
	 added as the first child of the collapsed/expanded content
	 element. I rebuild my breadcrumb children from the bound
	 coder's module + function/arity."
	self removeChildren.
	self addChildren: self buildBreadcrumb
]

{ #category : 'private' }
ElixirFunctionCoderHeaderElement >> populateForModule: aModuleName functionName: aFunctionName arity: anArity application: anApplication [
	"Direct population path — bypasses textualCoderViewModel
	 because callers like the |> expander already know the target."
	self removeChildren.
	self
		addChildren: (self
			buildButtonsForModule: aModuleName
			functionName: aFunctionName
			arity: anArity
			application: anApplication)
]
