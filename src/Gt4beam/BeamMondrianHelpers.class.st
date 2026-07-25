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

{ #category : 'uml' }
BeamMondrianHelpers class >> associationEdgeStencil [
	"UmlClassDiagram's association arc: orange, curved, behind nodes."
	| color |
	color := Color orange alpha: 0.4.
	^ [ :e |
		BlParabollaArcElement new
			zIndex: -1;
			curvatureFraction: 0.2;
			border: (BlBorder paint: color);
			toHead: (BlArrowheadSimpleArrow new border: (BlBorder paint: color)) ]
]

{ #category : 'labeled-graph' }
BeamMondrianHelpers class >> colorFor: aNode [
	"I return the role-based background color for `aNode`:
	 - dispatcher / cache root classes  -> pink   (#fce8e6)
	 - Announcement event classes       -> yellow (#fff8d6)
	 - BeamModuleSourceCache instances  -> green  (#d4f1d4) -- cache writer
	 - Announcer instances              -> blue   (#e8f0fe)
	 - everything else                  -> gray   (consumer classes / groups)"
	aNode isClass ifTrue: [
		(aNode == BeamEventAnnouncer or: [ aNode == BeamModuleSourceCache ])
			ifTrue: [ ^ Color fromHexString: '#fce8e6' ].
		(aNode inheritsFrom: Announcement)
			ifTrue: [ ^ Color fromHexString: '#fff8d6' ].
		^ Color gray alpha: 0.15 ].
	(aNode isKindOf: BeamModuleSourceCache)
		ifTrue: [ ^ Color fromHexString: '#d4f1d4' ].
	(aNode isKindOf: Announcer)
		ifTrue: [ ^ Color fromHexString: '#e8f0fe' ].
	^ Color gray alpha: 0.15
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
			short := n withoutPrefix: 'Elixir.'.
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
		#label -> ((node attributeAt: #name) withoutPrefix: 'Elixir.').
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

{ #category : 'uml' }
BeamMondrianHelpers class >> implementsEdgeStencil [
	"UmlClassDiagram's realization arrow: gray line, hollow triangle
	 at the interface (from) end."
	^ [ :e |
		BlLineElement new
			border: (BlBorder paint: Color gray);
			fromHead: (BlArrowheadTriangle new
				scale: 4;
				border: (BlBorder paint: Color gray)) ]
]

{ #category : 'uml' }
BeamMondrianHelpers class >> moduleLabelNamed: aName onClick: aBlock [
	"UmlClassDiagram's plain class box: a bordered label."
	^ BrLabel new
		aptitude: BrGlamorousLabelAptitude new;
		text: (aName withoutPrefix: 'Elixir.');
		border: (BlBorder paint: Color lightGray);
		background: Color white;
		padding: (BlInsets all: 5);
		addEventHandlerOn: BlClickEvent do: aBlock;
		yourself
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

{ #category : 'uml' }
BeamMondrianHelpers class >> paintInterfaceGraphOn: m kinds: kinds sigs: sigsByName edges: edges assocEdges: assocEdges eval: evalBlock [
	"I paint an interface -> implementor UML graph: boxes for
	 interfaces, labels for modules, implements triangles, orange
	 call arcs (passive, so the tree layout stays put). evalBlock
	 runs an expression on the bridge; module names spawn module
	 docs, signature rows spawn their function's docs."
	| spawn |
	spawn := [ :evt :name |
		evt consumed: true.
		evt currentTarget phlow spawnObject:
			(evalBlock value: 'GtBridge.Documentation.for_module(', name, ')') ].
	m nodes
		shape: [ :name |
			(kinds at: name) = #interface
				ifTrue: [
					| sigs |
					sigs := sigsByName at: name ifAbsent: [ nil ].
					self
						umlBoxNamed: name
						signatures: (sigs isNil
							ifTrue: [ #() ]
							ifFalse: [ sigs asList collect: [ :s | s asString ] ])
						onClick: [ :evt | spawn value: evt value: name ]
						onSignatureClick: [ :sig :evt |
							| parts |
							parts := $/ split: sig.
							evt currentTarget phlow spawnObject:
								(evalBlock value: 'GtBridge.Documentation.for_function(',
									name, ', :"', parts first, '", ', parts last, ')') ] ]
				ifFalse: [
					self moduleLabelNamed: name
						onClick: [ :evt | spawn value: evt value: name ] ] ];
		with: kinds keys asArray sorted.
	m edges
		stencil: self implementsEdgeStencil;
		connect: edges from: #key to: #value.
	assocEdges isEmpty ifFalse: [
		m edges
			passive;
			stencil: self associationEdgeStencil;
			connect: assocEdges from: #key to: #value ].
	m layout tree levelDistance: 40; nodeDistance: 15
]

{ #category : 'labeled-graph' }
BeamMondrianHelpers class >> paintLabeledGraphOn: aMondrian nodes: nodes edges: edges labels: labels layout: aLayoutBlock [
	"I render the boilerplate shared by every gt-view that paints the
	 BEAM event-architecture node graphs.  Node colors come from
	 `colorFor:` (role-based by node kind), so callers only supply
	 nodes, edges and labels.  `aLayoutBlock` receives `aMondrian
	 layout` so the caller can pick `tree` vs `horizontalTree` plus
	 distances."
	aMondrian nodes
		shape: [ :n |
			BrLabel new
				aptitude: BrGlamorousLabelAptitude new;
				text: (labels at: n);
				padding: (BlInsets all: 6);
				background: (self colorFor: n);
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

{ #category : 'uml' }
BeamMondrianHelpers class >> umlBoxNamed: aName signatures: sigLines onClick: aBlock onSignatureClick: aSigBlock [
	"GT's UML class box (UmlClassDiagram style): bold name
	 compartment over a signature compartment. The box itself fires
	 aBlock; each signature line fires aSigBlock (sig, event) and
	 consumes, so a row click doesn't also spawn the module."
	| uml nameText methodsText |
	uml := BrUmlClassElement withContainers: #(label methods).
	nameText := (aName withoutPrefix: 'Elixir.') asRopedText bold.
	nameText attributes: { BrTextClickAttribute new
		action: [ :aPiece :anElement :anEditor :anEvent |
			anEvent consumed: true.
			aBlock value: anEvent ] }.
	uml text: nameText in: #label.
	methodsText := '' asRopedText.
	sigLines doWithIndex: [ :sig :i |
		| line |
		line := sig asRopedText.
		line attributes: { BrTextClickAttribute new
			action: [ :aPiece :anElement :anEditor :anEvent |
				anEvent consumed: true.
				aSigBlock value: sig value: anEvent ] }.
		i > 1 ifTrue: [ methodsText append: String cr asRopedText ].
		methodsText append: line ].
	uml text: methodsText in: #methods.
	^ uml
		background: Color white;
		constraintsDo: [ :c |
			c horizontal fitContent.
			c vertical fitContent ];
		addEventHandlerOn: BlClickEvent do: aBlock;
		yourself
]
