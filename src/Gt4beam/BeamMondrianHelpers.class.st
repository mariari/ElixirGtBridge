Class {
	#name : 'BeamMondrianHelpers',
	#superclass : 'Object',
	#category : 'Gt4beam-Analysis',
	#package : 'Gt4beam',
	#tag : 'Analysis'
}

{ #category : 'dependency-tree' }
BeamMondrianHelpers class >> appDepGraphOn: aMondrian trees: trees apps: appsByName color: aColor [
	"I render an application dependency graph into aMondrian.
	 trees is a list of server-side {name, children} dictionaries;
	 appsByName maps app name strings to ElixirApplicationAnalysis so
	 clicking a node spawns the matching app."
	| nodes edges |
	nodes := OrderedCollection new.
	edges := OrderedCollection new.
	trees do: [ :tree | self flattenDepTree: tree into: nodes edges: edges ].
	aMondrian nodes
		stencil: [ :nodeName |
			| el |
			el := self nodeLabeled: nodeName color: aColor onClick: [ :evt | ].
			el addEventHandlerOn: BlClickEvent do: [ :evt |
				evt consumed: true.
				evt currentTarget phlow spawnObject:
					(appsByName at: nodeName ifAbsent: [ nodeName ]) ].
			el ];
		with: nodes.
	aMondrian edges stencil: [ self edgeStencil ];
		connect: edges from: #key to: #value.
	aMondrian layout horizontalDominanceTree
]

{ #category : 'compile deps' }
BeamMondrianHelpers class >> compileDepsOn: aMondrian edges: edges highlightModules: highlightSet application: anApp [
	"I render a compile dependency graph. Modules in highlightSet
	 are colored blue, others light gray. Clicking spawns docs."
	| allNodes |
	edges ifEmpty: [ ^ self ].
	allNodes := ((edges collect: [ :e |
		(e attributeAt: #from) asString ])
		, (edges collect: [ :e |
		(e attributeAt: #to) asString ])) asSet asArray sorted.
	aMondrian nodes
		shape: [ :n |
			| short color el |
			short := n copyReplaceAll: 'Elixir.' with: ''.
			color := (highlightSet includes: n)
				ifTrue: [ Color fromHexString: '#d4e6f1' ]
				ifFalse: [ Color fromHexString: '#f0f0f0' ].
			el := BrLabel new
				aptitude: BrGlamorousLabelAptitude new;
				text: short;
				padding: (BlInsets all: 4);
				background: color;
				geometry: (BlRoundedRectangleGeometry cornerRadius: 4).
			el addEventHandlerOn: BlClickEvent do: [ :evt |
				evt consumed: true.
				evt currentTarget phlow spawnObject:
					(anApp evaluateAndWait:
						'GtBridge.Documentation.for_module(', n, ')') ].
			el ];
		with: allNodes.
	aMondrian edges
		stencil: [ self edgeStencil ];
		connect: edges
			from: [ :e | (e attributeAt: #from) asString ]
			to: [ :e | (e attributeAt: #to) asString ].
	aMondrian layout horizontalDominanceTree
		nodeDistance: 10;
		levelDistance: 40
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

{ #category : 'dependency-tree' }
BeamMondrianHelpers class >> flattenDepTree: node into: nodes edges: edges [
	"I walk a server-side dependency tree and collect unique node names
	 plus the direct parent→child edges between them."
	| nodeName |
	nodeName := (node attributeAt: #name) asString.
	(nodes includes: nodeName) ifTrue: [ ^ self ].
	nodes add: nodeName.
	(node attributeAt: #children) asList do: [ :child |
		edges add: nodeName -> (child attributeAt: #name) asString.
		self flattenDepTree: child into: nodes edges: edges ]
]

{ #category : 'supervision' }
BeamMondrianHelpers class >> flattenTree: node into: nodes edges: edges poolThreshold: threshold [
	"I recursively flatten a supervision tree, collapsing large worker pools."
	| id children entry |
	id := node attributeAt: #pid.
	children := (node attributeAt: #children) asList.
	entry := {
		#id -> id.
		#pid -> id.
		#label -> ((node attributeAt: #name) copyReplaceAll: 'Elixir.' with: '').
		#supervisor -> (node attributeAt: #supervisor)
	} asDictionary.
	nodes add: entry.
	children size > threshold ifTrue: [
		| poolEntry |
		poolEntry := {
			#id -> (id , '_pool').
			#pid -> id.
			#label -> (children size asString , ' workers').
			#supervisor -> false.
			#pool -> true.
			#children -> children
		} asDictionary.
		nodes add: poolEntry.
		edges add: entry -> poolEntry.
		^ self ].
	children do: [ :child |
		| childEntry |
		self flattenTree: child into: nodes edges: edges poolThreshold: threshold.
		childEntry := nodes detect: [ :n | (n at: #id) = (child attributeAt: #pid) ].
		edges add: entry -> childEntry ]
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
		when: BlClickEvent do: [ :evt | evt consumed: true. aBlock value: evt ];
		constraintsDo: [ :c |
			c horizontal fitContent.
			c vertical fitContent ]
]

{ #category : 'labeled-graph' }
BeamMondrianHelpers class >> paintLabeledGraphOn: aMondrian nodes: nodes edges: edges labels: labels colors: colors layout: aLayoutBlock [
	"I render the boilerplate shared by every gt-view that paints a
	 labeled+colored node graph (BeamEventAnnouncer fanout, the
	 BeamModuleAnnouncement subscriber view, the three
	 BeamModuleSourceCache views).  Callers populate `nodes`,
	 `edges`, `labels` and `colors` with their domain-specific data;
	 I run the same `BrLabel` stencil + edge connect + layout dance.

	 `aLayoutBlock` receives `aMondrian layout` so the caller can
	 pick `horizontalTree` vs `verticalTree` plus distances; that's
	 the only piece that varies between callers."
	aMondrian nodes
		shape: [ :n |
			BrLabel new
				aptitude: BrGlamorousLabelAptitude new;
				text: (labels at: n);
				padding: (BlInsets all: 6);
				background: (colors at: n);
				geometry: (BlRoundedRectangleGeometry cornerRadius: 6) ];
		with: nodes asArray.
	aMondrian edges
		connect: edges asArray from: #key to: #value.
	aLayoutBlock value: aMondrian layout
]

{ #category : 'labeled-graph' }
BeamMondrianHelpers class >> subscribersOf: anAnnouncer [
	"I return the receiver objects subscribed to `anAnnouncer`,
	 swallowing missing-API errors with an empty array.  Used by
	 the FRP-shape gt-views that introspect Announcer state."
	^ [ anAnnouncer subscriptions subscriptions
		ifNil: [ #() ]
		ifNotNil: [ :subs | subs collect: [ :s | s subscriber ] ] ]
		on: Error do: [ #() ]
]

{ #category : 'supervision' }
BeamMondrianHelpers class >> supervisionTreeOn: aMondrian from: tree poolThreshold: threshold application: anApp [
	"I render a colored supervision tree with pool collapsing."
	| allNodes allEdges |
	allNodes := OrderedCollection new.
	allEdges := OrderedCollection new.
	self flattenTree: tree into: allNodes edges: allEdges poolThreshold: threshold.
	aMondrian nodes
		stencil: [ :node |
			| label color isSup isPool el |
			label := node at: #label.
			isSup := node at: #supervisor.
			isPool := node at: #pool ifAbsent: [ false ].
			color := isPool
				ifTrue: [ Color fromHexString: '#fff3cd' ]
				ifFalse: [ isSup
					ifTrue: [ Color fromHexString: '#d4e6f1' ]
					ifFalse: [ Color fromHexString: '#d5f5e3' ] ].
			el := self nodeLabeled: label color: color onClick: [ :evt | ].
			el addEventHandlerOn: BlClickEvent do: [ :evt |
				| pidStr cleaned expr |
				evt consumed: true.
				pidStr := node at: #pid ifAbsent: [ nil ].
				pidStr ifNotNil: [
					expr := (isPool or: [ label beginsWith: '#PID' ])
						ifTrue: [
							cleaned := (pidStr copyReplaceAll: '#PID<' with: '') copyReplaceAll: '>' with: ''.
							'IEx.Helpers.pid("', cleaned, '")' ]
						ifFalse: [ label first = $:
							ifTrue: [ label ]
							ifFalse: [ 'Elixir.', label ] ].
					evt currentTarget phlow spawnObject:
						(anApp newCommandFactory << expr; sendAndWait) ] ].
			el ];
		with: allNodes.
	aMondrian edges stencil: [ self edgeStencil ];
		connect: allEdges from: #key to: #value.
	aMondrian layout horizontalTree
]
