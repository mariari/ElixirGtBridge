Class {
	#name : 'ElixirModuleCoderElement',
	#superclass : 'BlElement',
	#traits : 'TBrLayoutResizable',
	#classTraits : 'TBrLayoutResizable classTrait',
	#instVars : [
		'coderViewModel',
		'coderPane',
		'browserPane'
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
ElixirModuleCoderElement >> beDetailedLevel [
	self beLevelState: GtPhlowToolDetailState detailed
]

{ #category : 'level' }
ElixirModuleCoderElement >> beLevelState: aGtPhlowToolDetailState [
	self states addState: aGtPhlowToolDetailState.
	self updateForLevel
]

{ #category : 'level' }
ElixirModuleCoderElement >> beNormalLevel [
	self beLevelState: GtPhlowToolDetailState normal
]

{ #category : 'building' }
ElixirModuleCoderElement >> buildUI [
	self removeChildren.
	browserPane := nil.
	coderPane := self buildContentPane.
	self addChild: coderPane
]

{ #category : 'level' }
ElixirModuleCoderElement >> effectiveDetailLevel [
	"My own level state wins; otherwise the nearest ancestor's, the way
	 the maximizer marks the tool root rather than every descendant."
	| el |
	el := self.
	[ el isNotNil ] whileTrue: [
		el states
			stateLike: GtPhlowToolDetailState normal
			ifFound: [ :aState | ^ aState ]
			ifNone: [  ].
		el := el parent ].
	^ GtPhlowToolDetailState normal
]

{ #category : 'level' }
ElixirModuleCoderElement >> hasParent: aClass [
	| el |
	el := self parent.
	[ el isNotNil ] whileTrue: [
		(el isKindOf: aClass) ifTrue: [ ^ true ].
		el := el parent ].
	^ false
]

{ #category : 'level' }
ElixirModuleCoderElement >> isDetailedLevel [
	^ self effectiveDetailLevel = GtPhlowToolDetailState detailed
]

{ #category : 'level' }
ElixirModuleCoderElement >> onAddedToSceneGraph [
	"Maximize and restore both re-parent the tool subtree, so attach is
	 the moment to re-read the effective level."
	super onAddedToSceneGraph.
	self updateForLevel
]

{ #category : 'level' }
ElixirModuleCoderElement >> newBrowserPane [
	"Scope the browser to my module's application when the BEAM can name
	 it; fall back to the unscoped browser. Content is my own pane, so
	 only the sidebar needs focusing."
	| appName browser |
	appName := [ (self coder application evaluateAndWait:
		'Application.get_application(', self coder moduleName, ') |> Kernel.to_string()') asString ]
		on: Error do: [ '' ].
	browser := appName isEmpty
		ifTrue: [ ElixirCoderBrowser forApplication: self coder application ]
		ifFalse: [ ElixirCoderBrowser forApplication: self coder application scopedTo: appName ].
	browser focusSidebarOn: self coder moduleName.
	^ browser
]

{ #category : 'level' }
ElixirModuleCoderElement >> showBrowserPane [
	"The detailed level is the module browser hosting my live coder
	 pane, so expanded rows and edits survive the flip.  Inside a
	 browser I stay a plain coder: the browser embeds inspectors whose
	 coders would otherwise recurse without end."
	coderViewModel ifNil: [ ^ self ].
	(self hasParent: ElixirCoderBrowser) ifTrue: [ ^ self showCoderPane ].
	browserPane ifNil: [ browserPane := self newBrowserPane ].
	browserPane showContentElement: coderPane.
	browserPane parent ifNil: [ self addChild: browserPane ]
]

{ #category : 'level' }
ElixirModuleCoderElement >> retargetTo: aModuleName [
	"Follow the module chosen in the browser."
	| app |
	app := self coder application.
	self coderViewModel: (ElixirModuleCoder forModule: aModuleName application: app) asCoderViewModel
]

{ #category : 'level' }
ElixirModuleCoderElement >> showCoderPane [
	"The normal level is the plain module coder, reclaimed from the
	 browser — or rebuilt for the module chosen there."
	browserPane ifNotNil: [ :pane |
		pane removeFromParent.
		(pane focusedModuleName isNotNil
			and: [ pane focusedModuleName ~= self coder moduleName ])
			ifTrue: [ ^ self retargetTo: pane focusedModuleName ] ].
	coderPane ifNotNil: [ :pane |
		pane parent == self ifFalse: [
			pane removeFromParent.
			self addChild: pane ] ]
]

{ #category : 'level' }
ElixirModuleCoderElement >> updateForLevel [
	self isDetailedLevel
		ifTrue: [ self showBrowserPane ]
		ifFalse: [ self showCoderPane ]
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
