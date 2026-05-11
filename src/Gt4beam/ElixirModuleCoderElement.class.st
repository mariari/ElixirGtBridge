Class {
	#name : 'ElixirModuleCoderElement',
	#superclass : 'BlElement',
	#traits : 'TBrLayoutResizable',
	#classTraits : 'TBrLayoutResizable classTrait',
	#instVars : [
		'coderViewModel'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'as yet unclassified' }
ElixirModuleCoderElement >> buildContentPane [
	| pane |
	pane := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical matchParent ];
		padding: (BlInsets top: 5 left: 6 bottom: 5 right: 6).
	pane addChild: self buildHeader.
	pane addChild: self buildContentTabs.
	^ pane
]

{ #category : 'as yet unclassified' }
ElixirModuleCoderElement >> buildContentTabs [
	"I collect views via #gtElixirModuleView pragmas on the coder."
	| coder context |
	coder := self coder.
	context := GtPhlowContext new.
	context optionAt: #moduleCoder put: coderViewModel.
	^ GtPhlowCompositeView new
		object: coder
			arguments: { GtPhlowView empty. context };
		collectorDo: [ :aCollector |
			aCollector
				context: context;
				fromObject: coder;
				from: coder class;
				to: ElixirModuleCoder;
				pragmaName: #gtElixirModuleView ];
		asElementDo: [ :aTabGroup | aTabGroup ]
]

{ #category : 'building' }
ElixirModuleCoderElement >> buildHeader [
	| container nameLabel |
	container := BrHorizontalPane new
		hMatchParent;
		vFitContent;
		alignCenterLeft;
		padding: (BlInsets top: 5 left: 6 bottom: 5 right: 6).
	nameLabel := BrLabel new
		aptitude: (BrGlamorousLabelAptitude new glamorousCodeFont; bold; fontSize: 16);
		text: self coder moduleName.
	container addChild: nameLabel.
	container addChild: (BrFrame new vFitContent; hMatchParent).
	container addChild: (BrButton new
		aptitude: BrGlamorousButtonWithIconAptitude;
		icon: BrGlamorousVectorIcons accept; beSmallSize;
		label: 'Save & compile';
		action: [ :btn |
			btn phlow spawnObject:
				(self coder saveAndCompile: self coder sourceCode) ]).
	self coder hasLocalSource ifTrue: [
		container addChild: self buildRemoveModuleButton ].
	^ container
]

{ #category : 'building' }
ElixirModuleCoderElement >> buildRemoveModuleButton [
	"I render a trash button next to Save&Compile that, on click,
	 opens a dropdown with the module name + source path + an inner
	 trash button. The destructive action is the inner button —
	 clicking the outer icon alone only opens the dropdown."
	^ BrButton new
		aptitude: BrGlamorousButtonWithIconAptitude;
		icon: BrGlamorousVectorIcons bin;
		beSmallSize;
		label: 'Remove module';
		addAptitude: (BrGlamorousWithDropdownAptitude
			handle: [
				BrButton new
					aptitude: BrGlamorousButtonWithIconAptitude;
					icon: BrGlamorousVectorIcons bin;
					beSmallSize;
					label: 'Remove module' ]
			content: [
				BrVerticalPane new
					fitContent;
					margin: (BlInsets all: 10);
					addChild: (BrLabel new
						aptitude: BrGlamorousLabelAptitude new;
						text: 'Remove module ', self coder moduleName);
					addChild: (BrLabel new
						aptitude: (BrGlamorousLabelAptitude new
							foreground: BrGlamorousColors disabledButtonTextColor);
						text: self coder sourcePath;
						margin: (BlInsets top: 4 bottom: 8));
					addChild: (BrButton new
						aptitude: BrGlamorousButtonWithIconAptitude;
						icon: BrGlamorousVectorIcons bin;
						beTinySize;
						action: [ :aButton | self coder remove ];
						yourself);
					yourself ])
]

{ #category : 'building' }
ElixirModuleCoderElement >> buildUI [
	self removeChildren.
	self addChild: self buildContentPane
]

{ #category : 'accessing' }
ElixirModuleCoderElement >> coder [
	^ coderViewModel coder
]

{ #category : 'accessing' }
ElixirModuleCoderElement >> coderViewModel: aCoderViewModel [
	coderViewModel := aCoderViewModel.
	self buildUI
]

{ #category : 'initialization' }
ElixirModuleCoderElement >> initialize [
	super initialize.
	self
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical matchParent ]
]
