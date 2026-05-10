Class {
	#name : 'ElixirCoderBrowser',
	#superclass : 'BlElement',
	#instVars : [
		'application',
		'sidebar',
		'content',
		'scopedApplicationName',
		'filterText',
		'rawNodes'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'as yet unclassified' }
ElixirCoderBrowser class >> forApplication: anApp [
	"I return an unscoped browser showing every loaded application
	 on the BEAM as the top level of the sidebar tree."
	^ self new application: anApp; yourself
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser class >> forApplicationAnalysis: anElixirApplicationAnalysis [
	"I return a browser scoped to a single Elixir application. The
	 sidebar hides the application-level wrapper and shows the app's
	 modules grouped by namespace at the top level.
	 Uses name symbol (not asString) because BeamAtomObject's asString
	 goes through printOn: which decorates the string — we need the
	 raw symbol to build a valid :atom literal on the bridge side."
	^ self new
		scopedApplicationName: anElixirApplicationAnalysis name symbol;
		application: anElixirApplicationAnalysis application;
		yourself
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> appNode: anAppName [
	"I build a tree node for a single application with its modules
	 grouped by namespace under the app. The #appName key lets the
	 send: block spawn the matching ElixirApplicationAnalysis when
	 the user clicks on the app row itself (vs. a module leaf)."
	| appNode modules |
	appNode := Dictionary new.
	appNode at: #label put: anAppName.
	appNode at: #appName put: anAppName.
	modules := [ self moduleInfoForApplication: anAppName ]
		on: Error do: [ #() ].
	appNode at: #children put: (self groupModulesByNamespace: modules).
	^ appNode
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> application [
	^ application
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> application: anApp [
	application := anApp.
	self buildUI
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> applicationAnalysisFor: anAppName [
	"I build an ElixirSystemAnalysis on my bridge application and
	 return the ElixirApplicationAnalysis matching anAppName, or nil
	 if no such application is loaded."
	^ (ElixirSystemAnalysis onApplication: application) applications
		detect: [ :app | app name symbol = anAppName ]
		ifNone: [ nil ]
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> applicationNames [
	^ [ (application evaluateAndWait:
		'Application.loaded_applications()
		|> Enum.map(fn {name, _, _} -> Atom.to_string(name) end)
		|> Enum.sort()') asList collect: #asString ]
		on: Error do: [ #() ]
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> applicationNodes [
	"I return the sidebar's top-level tree nodes, filtered by
	 filterText when it's non-empty. The raw (unfiltered) nodes are
	 cached in rawNodes so filter rebuilds don't re-fetch from the
	 BEAM — the fetch happens once per browser instance, filtering is
	 pure Smalltalk after that."
	^ self filterNodes: self rawNodes
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> buildFilterInput [
	"I build a bordered live-filter input. Every keystroke refreshes
	 the sidebar tree, running filterNodes: against the already-cached
	 rawNodes — no bridge round-trip per character, so this stays
	 snappy on large applications."
	| input container |
	input := BrEditor new
		aptitude: BrGlamorousEditorAptitude new;
		text: (filterText ifNil: [ '' ]) asRopedText;
		hMatchParent;
		vFitContent.
	input editor
		when: BrTextEditorModifiedEvent
		do: [ :anEvent |
			filterText := input text asString.
			self refreshSidebarTree ].
	container := BlElement new
		layout: BlLinearLayout horizontal;
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical fitContent ];
		background: Color white;
		border: (BlBorder paint: (Color gray alpha: 0.5) width: 1);
		padding: (BlInsets top: 4 left: 6 bottom: 4 right: 6);
		margin: (BlInsets all: 4);
		addChild: (BrLabel new
			aptitude: (BrGlamorousLabelAptitude new
				foreground: (Color gray alpha: 0.7);
				fontSize: 10);
			text: 'Filter';
			margin: (BlInsets right: 6));
		addChild: input;
		yourself.
	^ container
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> buildNamespaceNode: label from: entries depth: depth [
	"I recursively group entries under this namespace level."
	| leaves branches branchGroups node |
	leaves := entries select: [ :e | e third size = depth ].
	branches := entries reject: [ :e | e third size = depth ].
	branchGroups := Dictionary new.
	branches do: [ :e |
		| key |
		key := e third at: depth + 1.
		(branchGroups at: key ifAbsentPut: [ OrderedCollection new ]) add: e ].
	node := Dictionary new.
	node at: #label put: label.
	leaves size = 1 ifTrue: [
		node at: #module put: leaves first first.
		node at: #functions put: (leaves first second attributeAt: #functions).
		node at: #has_doc put: (leaves first second attributeAt: #has_doc) ].
	node at: #children put: (
		((leaves size > 1 
			ifTrue: [ leaves collect: [ :e |
				| leaf |
				leaf := Dictionary new.
				leaf at: #label put: e third last.
				leaf at: #module put: e first.
				leaf at: #functions put: (e second attributeAt: #functions).
				leaf at: #has_doc put: (e second attributeAt: #has_doc).
				leaf at: #children put: #().
				leaf ] ]
			ifFalse: [ #() ]) ,
		(branchGroups keys sorted collect: [ :k |
			self buildNamespaceNode: k from: (branchGroups at: k) depth: depth + 1 ])) asArray).
	^ node
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> buildSidebar [
	"I build the sidebar: a vertical container with a filter input
	 on top and a namespace tree below. Keeping the input and tree
	 as separate children so the tree can be rebuilt in isolation
	 when the filter changes without tearing down the input."
	| container |
	container := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical matchParent ];
		addChild: self buildFilterInput;
		addChild: self buildSidebarTree;
		yourself.
	^ container
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> buildSidebarTree [
	"I build just the tree element (no filter input, no container).
	 Used on initial build and on filter-triggered rebuilds."
	| view element |
	view := GtPhlowColumnedTreeView new
		items: [ self applicationNodes ];
		children: [ :node | node at: #children ];
		expandUpTo: 10;
		column: 'Name' text: [ :node |
			(node at: #label) asString ];
		column: 'Fns' text: [ :node |
			(node at: #functions ifAbsent: [ nil ])
				ifNil: [ '' ]
				ifNotNil: [ :n | n asString ] ] width: 40;
		column: 'Docs' text: [ :node |
			(node at: #has_doc ifAbsent: [ nil ])
				ifNil: [ '' ]
				ifNotNil: [ :hd | hd ifTrue: [ '✓' ] ifFalse: [ 'Δ' ] ] ] width: 40;
		send: [ :node |
			| result |
			result := (node at: #module ifAbsent: [ nil ])
				ifNotNil: [ :name |
					application evaluateAndWait:
						'GtBridge.Documentation.for_module(', name, ')' ]
				ifNil: [
					(node at: #appName ifAbsent: [ nil ])
						ifNotNil: [ :appName | self applicationAnalysisFor: appName ] ].
			self openModule: result.
			result ].
	element := view asElementDo: [ :e | e ].
	element constraintsDo: [ :c |
		c horizontal matchParent.
		c vertical matchParent ].
	^ element
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> buildUI [
	"I show the sidebar on the left and a content pane on the right.
	 Clicking a module in the tree renders its documentation inline
	 in the content pane."
	self removeChildren.
	sidebar := self buildSidebar.
	sidebar constraintsDo: [ :c | c horizontal exact: 300 ].
	content := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical matchParent ];
		padding: (BlInsets all: 5).
	content addChild: (BrLabel new
		aptitude: (BrGlamorousLabelAptitude new foreground: Color gray);
		text: 'Select a module from the sidebar').
	self addChild: sidebar.
	self addChild: content
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> filterNode: aNode [
	"I return a filtered copy of aNode, or nil when neither the node
	 nor any descendant matches filterText. Matches are substring,
	 case-insensitive, against the node's label and module name."
	| lowerFilter children filteredChildren labelMatches nameMatches selfMatches copy |
	lowerFilter := filterText asLowercase.
	labelMatches := ((aNode at: #label ifAbsent: [ '' ]) asString asLowercase
		includesSubstring: lowerFilter).
	nameMatches := (aNode at: #module ifAbsent: [ nil ])
		ifNil: [ false ]
		ifNotNil: [ :name | name asLowercase includesSubstring: lowerFilter ].
	selfMatches := labelMatches or: [ nameMatches ].
	children := (aNode at: #children ifAbsent: [ #() ]) asArray.
	filteredChildren := selfMatches
		ifTrue: [ children ]
		ifFalse: [
			(children collect: [ :c | self filterNode: c ])
				select: [ :c | c notNil ] ].
	(selfMatches or: [ filteredChildren notEmpty ]) ifFalse: [ ^ nil ].
	copy := Dictionary new.
	aNode associationsDo: [ :assoc |
		copy at: assoc key put: assoc value ].
	copy at: #children put: filteredChildren asArray.
	^ copy
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> filterNodes: nodes [
	"I return nodes filtered by filterText. A branch is kept if its
	 label matches or any descendant matches. A leaf is kept if its
	 label or its full #module name matches. Empty filterText means
	 pass everything through unchanged."
	(filterText isNil or: [ filterText isEmpty ])
		ifTrue: [ ^ nodes ].
	^ nodes
		collect: [ :node | self filterNode: node ]
		thenSelect: [ :node | node notNil ]
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> groupModulesByNamespace: moduleInfo [
	"I group modules by their dotted namespace, returning a tree of nodes."
	| groups entries |
	entries := moduleInfo collect: [ :each |
		| name parts |
		name := (each attributeAt: #name) asString.
		parts := $. split: (name withoutPrefix: 'Elixir.').
		{ name. each. parts } ].
	groups := Dictionary new.
	entries do: [ :e |
		| key |
		key := e third first.
		(groups at: key ifAbsentPut: [ OrderedCollection new ]) add: e ].
	^ (groups keys sorted collect: [ :key |
		self buildNamespaceNode: key from: (groups at: key) depth: 1 ]) asArray
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> initialize [
	super initialize.
	self layout: BlLinearLayout horizontal.
	self constraintsDo: [ :c |
		c horizontal matchParent.
		c vertical matchParent ]
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> moduleInfoForApplication: anAppName [
	"I return module details for the given application."
	^ (application evaluateAndWait:
		'GtBridge.Analysis.module_details(:', anAppName, ')') asList
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> modulesForApplication: anAppName [
	^ [ (application evaluateAndWait:
		'GtBridge.Analysis.module_details(:', anAppName, ')') asList
			collect: [ :m | (m attributeAt: #name) asString ] ]
		on: Error do: [ #() ]
]

{ #category : 'lifecycle' }
ElixirCoderBrowser >> onAddedToSceneGraph [
	"I subscribe to the wildcard `default` announcer (not a per-module
	 one) because I display ALL loaded modules and need to invalidate
	 my rawNodes cache on any recompile, not just one module's. The
	 narrow per-module pattern is for coders attached to a specific
	 module; my browsing surface inherently spans every module so the
	 default singleton is the right channel.

	 I subscribe only while in the scene graph — background or
	 orphaned browser instances do not pay the per-event cost."
	super onAddedToSceneGraph.
	BeamEventAnnouncer default weak
		when: BeamModuleRecompiled
		send: #onBeamModuleRecompiled:
		to: self
]

{ #category : 'announcements' }
ElixirCoderBrowser >> onBeamModuleRecompiled: anAnnouncement [
	"I just invalidate the cached node tree. I do NOT auto-refresh
	 the sidebar — refreshSidebarTree fans out applicationNodes which
	 (when unscoped) hits every loaded app via module_details, easily
	 50+ BEAM round trips. Per save. Per live browser. That overloaded
	 the bridge into request-fail cascades.

	 Next time the user interacts with the filter input or otherwise
	 triggers refreshSidebarTree, the lazy rawNodes will refetch
	 from scratch. Trade auto-refresh UX for resource safety until
	 a smaller-blast-radius refresh path is available."
	rawNodes := nil
]

{ #category : 'lifecycle' }
ElixirCoderBrowser >> onRemovedFromSceneGraph [
	"I unsubscribe when removed so recompile events stop reaching me
	 the moment my window closes."
	super onRemovedFromSceneGraph.
	BeamEventAnnouncer default unsubscribe: self
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> openModule: aDocObject [
	"I render a BeamDocumentationObject inline in the content pane
	 using the composite inspector tool with R|P toggle."
	| element |
	aDocObject ifNil: [ ^ self ].
	element := aDocObject gtDefaultInspectorTool
		asElementDo: [ :e | e matchParent ].
	content removeChildren.
	content addChild: element
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> rawNodes [
	"I lazily fetch and cache the unfiltered top-level nodes. When
	 scoped to a single application, I skip the app wrapper and
	 return the module namespace groups directly. Otherwise I return
	 one node per loaded application with modules nested underneath."
	^ rawNodes ifNil: [ rawNodes := scopedApplicationName
		ifNotNil: [
			| modules |
			modules := [ self moduleInfoForApplication: scopedApplicationName ]
				on: Error do: [ #() ].
			self groupModulesByNamespace: modules ]
		ifNil: [
			self applicationNames collect: [ :appName | self appNode: appName ] ] ]
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> openModule: aDocObject [
	"I render a BeamDocumentationObject inline in the content pane
	 using the composite inspector tool with R|P toggle."
	| element |
	aDocObject ifNil: [ ^ self ].
	element := aDocObject gtDefaultInspectorTool
		asElementDo: [ :e | e matchParent ].
	content removeChildren.
	content addChild: element
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> rawNodes [
	"I lazily fetch and cache the unfiltered top-level nodes. When
	 scoped to a single application, I skip the app wrapper and
	 return the module namespace groups directly. Otherwise I return
	 one node per loaded application with modules nested underneath."
	^ rawNodes ifNil: [ rawNodes := scopedApplicationName
		ifNotNil: [
			| modules |
			modules := [ self moduleInfoForApplication: scopedApplicationName ]
				on: Error do: [ #() ].
			self groupModulesByNamespace: modules ]
		ifNil: [
			self applicationNames collect: [ :appName | self appNode: appName ] ] ]
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> refreshSidebarTree [
	"I replace the sidebar's tree child with a fresh one built from
	 the current filterText. Called by the filter input on every
	 keystroke. Only the tree (sidebar's second child) is replaced —
	 the filter input (first child) stays so its focus and cursor
	 position are preserved while the user is still typing."
	sidebar ifNil: [ ^ self ].
	sidebar children size >= 2 ifTrue: [
		sidebar children second removeFromParent ].
	sidebar addChild: self buildSidebarTree
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> scopedApplicationName [
	^ scopedApplicationName
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> scopedApplicationName: aString [
	"I set the scope to a single application name. Must be called
	 before #application: since the setter triggers sidebar build."
	scopedApplicationName := aString
]
