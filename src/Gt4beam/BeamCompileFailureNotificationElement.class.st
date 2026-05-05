"
I render the compile-failure notification as a bordered box (title,
function/line, error message, Open button).
"
Class {
	#name : 'BeamCompileFailureNotificationElement',
	#superclass : 'GtNotificationEventElement',
	#instVars : [
		'titleLabel',
		'functionLabel',
		'messageLabel',
		'openButton'
	],
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}

{ #category : 'initialization' }
BeamCompileFailureNotificationElement >> initialize [
	super initialize.
	titleLabel := BrLabel new
		aptitude: (BrGlamorousLabelAptitude new bold);
		hMatchParent;
		text: ''.
	functionLabel := BrLabel new
		aptitude: BrGlamorousLabelAptitude new;
		hMatchParent;
		text: ''.
	messageLabel := BrLabel new
		aptitude: BrGlamorousLabelAptitude new;
		hMatchParent;
		text: ''.
	openButton := BrButton new
		aptitude: BrGlamorousButtonWithLabelAptitude new;
		label: 'Open';
		margin: (BlInsets top: 6);
		action: [ :btn | self openCoderFrom: btn ].
	self
		layout: BlLinearLayout vertical;
		padding: (BlInsets all: 8);
		background: (Color fromHexString: 'FCEFEF');
		border: (BlBorder paint: (Color fromHexString: 'D44A4A') width: 1);
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical fitContent ].
	self addChild: titleLabel.
	self addChild: functionLabel.
	self addChild: messageLabel.
	self addChild: (BrHorizontalPane new
		hMatchParent;
		vFitContent;
		alignBottomRight;
		addChild: openButton;
		yourself)
]

{ #category : 'subscriptions' }
BeamCompileFailureNotificationElement >> onNotificationChanged [
	(self notification isNil or: [ titleLabel isNil ]) ifTrue: [ ^ self ].
	self notification ifNotNil: [ :n |
		titleLabel text: n title.
		functionLabel text: n functionLineLabel.
		messageLabel text: n shortMessage.
		openButton enabled: n canOpen ]
]

{ #category : 'actions' }
BeamCompileFailureNotificationElement >> openCoderFrom: anElement [
	"Build a coder + ElixirModuleCoderElement (the composite Source/
	 Functions/Help element — bare `asCoderViewModel asElement` only
	 gives the source tab and skips the pragma-driven tabs that read
	 focusFunctionTarget) and show it in a fresh space."
	| n app coder element space |
	n := self notification.
	n ifNil: [ ^ self ].
	app := n resolveApplication.
	app ifNil: [ ^ self ].
	coder := ElixirModuleCoder
		forModule: n moduleName
		application: app
		sourcePath: n sourcePath.
	n hasFunction ifTrue: [ coder focusFunctionTarget: n functionTarget ].
	n hasLine ifTrue: [ coder focusLine: n line ].
	element := ElixirModuleCoderElement new
		coderViewModel: coder asCoderViewModel;
		yourself.
	space := BlSpace new
		title: n moduleName;
		extent: 800 @ 600;
		yourself.
	space root addChild: element matchParent.
	space show.
	self dismiss
]
