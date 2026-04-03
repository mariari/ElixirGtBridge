Class {
	#name : 'BeamMondrianHelpers',
	#superclass : 'Object',
	#category : 'Gt4beam-Analysis',
	#package : 'Gt4beam',
	#tag : 'Analysis'
}

{ #category : 'supervision' }
BeamMondrianHelpers class >> flattenTree: node into: nodes edges: edges poolThreshold: threshold [
	"I recursively flatten a supervision tree, collapsing large worker pools."
	| id label isSup children entry |
	id := node attributeAt: #pid.
	label := (node attributeAt: #name) copyReplaceAll: 'Elixir.' with: ''.
	isSup := node attributeAt: #supervisor.
	children := (node attributeAt: #children) asList.
	entry := Dictionary new.
	entry at: #id put: id.
	entry at: #pid put: id.
	entry at: #label put: label.
	entry at: #supervisor put: isSup.
	nodes add: entry.
	children size > threshold ifTrue: [
		| poolEntry |
		poolEntry := Dictionary new.
		poolEntry at: #id put: id , '_pool'.
		poolEntry at: #label put: children size asString , ' workers'.
		poolEntry at: #supervisor put: false.
		poolEntry at: #pool put: true.
		poolEntry at: #children put: children.
		nodes add: poolEntry.
		edges add: entry -> poolEntry.
		^ self ].
	children do: [ :child |
		| childEntry |
		self flattenTree: child into: nodes edges: edges poolThreshold: threshold.
		childEntry := nodes detect: [ :n | (n at: #id) = (child attributeAt: #pid) ].
		edges add: entry -> childEntry ]
]

{ #category : 'supervision' }
BeamMondrianHelpers class >> supervisionTreeOn: aMondrian from: tree poolThreshold: threshold [
	"I render a colored supervision tree with pool collapsing."
	| allNodes allEdges |
	allNodes := OrderedCollection new.
	allEdges := OrderedCollection new.
	self flattenTree: tree into: allNodes edges: allEdges poolThreshold: threshold.
	aMondrian nodes
		stencil: [ :node |
			| label color isSup isPool |
			label := node at: #label.
			isSup := node at: #supervisor.
			isPool := node at: #pool ifAbsent: [ false ].
			color := isPool
				ifTrue: [ Color fromHexString: '#fff3cd' ]
				ifFalse: [ isSup
					ifTrue: [ Color fromHexString: '#d4e6f1' ]
					ifFalse: [ Color fromHexString: '#d5f5e3' ] ].
			self
				nodeLabeled: label color: color
				onClick: [ :evt |
					isPool
						ifTrue: [ evt target phlow spawnObject: (node at: #children) ]
						ifFalse: [ evt target phlow spawnObject: (node at: #pid ifAbsent: [ node ]) ] ] ];
		with: allNodes.
	aMondrian edges stencil: [ self edgeStencil ];
		connect: allEdges from: #key to: #value.
	aMondrian layout horizontalTree
]

{ #category : 'stencils' }
BeamMondrianHelpers class >> edgeStencil [
	^ BlParabollaArcElement new
		zIndex: -1;
		curvatureFraction: 0.1;
		border: (BlBorder paint: (Color gray alpha: 0.4) width: 1);
		toHead: (BlArrowheadSimpleArrow new
			arrowLengthFraction: 5;
			arrowNoseAngle: 60;
			border: (BlBorder paint: (Color gray alpha: 0.4) width: 1))
]

{ #category : 'stencils' }
BeamMondrianHelpers class >> nodeLabeled: aString color: aColor onClick: aBlock [
	^ BrHorizontalPane new
		geometry: (BlRoundedRectangleGeometry cornerRadius: 3);
		border: (BlBorder paint: aColor darker width: 1);
		background: aColor;
		padding: (BlInsets all: 4);
		addChild: (BlTextElement new
			text: aString asRopedText glamorousRegularSmallSize;
			constraintsDo: [ :c |
				c horizontal fitContent.
				c vertical fitContent ]);
		when: BlClickEvent do: [ :evt | aBlock value: evt ];
		constraintsDo: [ :c |
			c horizontal fitContent.
			c vertical fitContent ]
]
