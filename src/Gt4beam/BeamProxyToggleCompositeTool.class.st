Class {
	#name : 'BeamProxyToggleCompositeTool',
	#superclass : 'GtPhlowCompositeTool',
	#instVars : [
		'subState',
		'currentToolName',
		'cachedProxies',
		'tabGroup',
		'rpBox'
	],
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'instance creation' }
BeamProxyToggleCompositeTool class >> fromModes: modes [
	"I build a composite tool from collected inspector modes."
	| composite |
	composite := self new.
	modes do: [ :mode | composite addTool: mode tool ].
	^ composite
]

{ #category : 'rendering' }
BeamProxyToggleCompositeTool >> asElementDo: aOneArgBlock [
	"I render as a standard composite tool with a compact R/P
	 toggle next to the selected tab label."
	currentToolName := self tools first name.
	tabGroup := BrTabGroup new
		id: #'Composite Tool';
		aptitude: BrGlamorousTabGroupSwitcherAptitude new.
	self tools do: [ :tool |
		tool asTabDo: [ :tab | tabGroup addTab: tab ] ].
	tabGroup addEventHandler: GtPhlowToolObjectChangeHandler new.
	tabGroup phlow toolViewModel:
		(GtPhlowToolCompositeViewModel new tabGroup: tabGroup).
	tabGroup enqueueTask: (BlTaskAction new action: [
		self installProxyToggle ]).
	^ aOneArgBlock cull: tabGroup
]

{ #category : 'private' }
BeamProxyToggleCompositeTool >> attachRpBoxToSelectedTab [
	"I move the R/P box to whichever tab element is selected."
	| tabBar |
	tabBar := tabGroup children second children first children first.
	rpBox removeFromParent.
	tabBar children do: [ :tabElem |
		tabElem viewModel isSelected ifTrue: [
			tabElem addChild: rpBox ] ]
]

{ #category : 'rendering' }
BeamProxyToggleCompositeTool >> buildToggleButton: aLabel active: aBoolean action: aBlock [
	"I build a single R or P button."
	^ BlElement new
		geometry: (BlRoundedRectangleGeometry cornerRadius: 2);
		layout: BlFrameLayout new;
		constraintsDo: [ :c |
			c horizontal fitContent. c vertical matchParent ];
		background: (aBoolean
			ifTrue: [ Color lightGray ] ifFalse: [ Color transparent ]);
		padding: (BlInsets top: 0 right: 6 bottom: 0 left: 6);
		addChild: (BrLabel new
			aptitude: (BrGlamorousLabelAptitude new fontSize: 9);
			text: (aLabel asRopedText foreground: Color black);
			constraintsDo: [ :c |
				c frame horizontal alignCenter.
				c frame vertical alignCenter ]);
		addEventHandlerOn: BlClickEvent do: [ :evt |
			evt consumed: true. aBlock value ]
]

{ #category : 'initialization' }
BeamProxyToggleCompositeTool >> initialize [
	super initialize.
	subState := 'Remote'.
	cachedProxies := Dictionary new
]

{ #category : 'rendering' }
BeamProxyToggleCompositeTool >> installProxyToggle [
	"I inject the R/P box into the selected tab and wire events."
	| rBtn pBtn |
	rBtn := self buildToggleButton: 'R' active: true
		action: [ subState := 'Remote'. self onProxyModeChanged ].
	rBtn id: 'beam-toggle-R'.
	pBtn := self buildToggleButton: 'P' active: false
		action: [ subState := 'Proxy'. self onProxyModeChanged ].
	pBtn id: 'beam-toggle-P'.
	rpBox := BlElement new
		layout: (BlLinearLayout horizontal cellSpacing: 0);
		constraintsDo: [ :c |
			c horizontal fitContent. c vertical matchParent ];
		geometry: (BlRoundedRectangleGeometry cornerRadius: 3);
		background: Color white;
		border: (BlBorder paint: (Color black alpha: 0.6) width: 1);
		clipChildren: true;
		margin: (BlInsets left: 6);
		addChildren: { rBtn. pBtn }.
	self attachRpBoxToSelectedTab.
	tabGroup when: BrTabSelectedEvent do: [ :evt |
		self onTabSelected ]
]

{ #category : 'private' }
BeamProxyToggleCompositeTool >> onProxyModeChanged [
	"I react to R/P toggle clicks — update highlights and swap content."
	rpBox children first background: (subState = 'Remote'
		ifTrue: [ Color lightGray ] ifFalse: [ Color transparent ]).
	rpBox children second background: (subState = 'Proxy'
		ifTrue: [ Color lightGray ] ifFalse: [ Color transparent ]).
	subState = 'Proxy'
		ifTrue: [
			| obj proxyTool elem |
			obj := (self tools detect: [ :t | t name = currentToolName ]) object.
			elem := cachedProxies at: currentToolName ifAbsentPut: [
				proxyTool := (obj respondsTo: #gtProxySideInspectorTool)
					ifTrue: [ obj gtProxySideInspectorTool ]
					ifFalse: [ GtPhlowTool default object: obj ].
				proxyTool
					playgroundPageStrategy: LeInspectorPlaygroundProxyClassPageStrategy forLocalProxySide;
					yourself.
				proxyTool asElementDo: [ :e | e ] ].
			tabGroup children first removeChildren.
			tabGroup children first addChild: elem ]
		ifFalse: [
			tabGroup tabs do: [ :t |
				t isSelected ifTrue: [ t deselect. t select ] ] ]
]

{ #category : 'private' }
BeamProxyToggleCompositeTool >> onTabSelected [
	"I track which tool is selected, move the R/P box, and reset
	 to Remote if needed."
	self tools withIndexDo: [ :tool :idx |
		(tabGroup tabs at: idx) isSelected ifTrue: [
			currentToolName := tool name ] ].
	subState = 'Proxy' ifTrue: [
		subState := 'Remote'.
		self onProxyModeChanged ].
	self attachRpBoxToSelectedTab
]

