"
I render the compile-failure notification: summary text + an Open
button that spawns the offending module's coder.
"
Class {
	#name : 'BeamCompileFailureNotificationElement',
	#superclass : 'GtNotificationEventElement',
	#instVars : [
		'summaryLabel',
		'openButton'
	],
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}

{ #category : 'initialization' }
BeamCompileFailureNotificationElement >> initialize [
	super initialize.
	self
		layout: BlLinearLayout horizontal alignCenter;
		padding: (BlInsets all: 6);
		background: BrGlamorousColors newsBackgroundColor;
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical fitContent ];
		aptitude: BrShadowAptitude.
	summaryLabel := BrLabel new
		aptitude: BrGlamorousLabelAptitude new;
		hMatchParent.
	openButton := BrButton new
		aptitude: BrGlamorousButtonWithLabelAptitude new;
		label: 'Open';
		margin: (BlInsets left: 10);
		action: [ :btn | self openCoderFrom: btn ].
	self addChild: summaryLabel.
	self addChild: openButton
]

{ #category : 'subscriptions' }
BeamCompileFailureNotificationElement >> onNotificationChanged [
	self notification ifNotNil: [ :n |
		summaryLabel text: n summary.
		openButton enabled: n canOpen ]
]

{ #category : 'actions' }
BeamCompileFailureNotificationElement >> openCoderFrom: anElement [
	"Build a coder for the offending module and spawn it via phlow.
	 Focus the failing line when known."
	| n app coder |
	n := self notification.
	n ifNil: [ ^ self ].
	app := n resolveApplication.
	app ifNil: [ ^ self ].
	coder := ElixirModuleCoder
		forModule: n moduleName
		application: app
		sourcePath: n sourcePath.
	n hasLine ifTrue: [ coder focusLine: n line ].
	anElement phlow spawnObject: coder.
	self dismiss
]
