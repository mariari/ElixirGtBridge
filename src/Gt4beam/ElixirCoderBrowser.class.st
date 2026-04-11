Class {
	#name : 'ElixirCoderBrowser',
	#superclass : 'BlElement',
	#instVars : [
		'application',
		'sidebar',
		'content',
		'scopedApplicationName'
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
ElixirCoderBrowser >> applicationAnalysisFor: anAppName [
	"I build an ElixirSystemAnalysis on my bridge application and
	 return the ElixirApplicationAnalysis matching anAppName, or nil
	 if no such application is loaded."
	^ (ElixirSystemAnalysis onApplication: application) applications
		detect: [ :app | app name symbol = anAppName ]
		ifNone: [ nil ]
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
ElixirCoderBrowser >> applicationNames [
	^ [ (application evaluateAndWait:
		'Application.loaded_applications()
		|> Enum.map(fn {name, _, _} -> Atom.to_string(name) end)
		|> Enum.sort()') asList collect: #asString ]
		on: Error do: [ #() ]
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> applicationNodes [
	"I return the sidebar's top-level tree nodes. When scoped to a
	 single application, I skip the app wrapper and return the module
	 namespace groups directly. Otherwise I return one node per loaded
	 application with modules nested underneath."
	scopedApplicationName ifNotNil: [
		| modules |
		modules := [ self moduleInfoForApplication: scopedApplicationName ]
			on: Error do: [ #() ].
		^ self groupModulesByNamespace: modules ].
	^ self applicationNames collect: [ :appName |
		self appNode: appName ]
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
	"I build a nested tree: applications -> namespace-grouped modules.
	 Fully expanded by default so users see the whole structure at once."
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
ElixirCoderBrowser >> openModule: aDocObject [
	"I render a BeamDocumentationObject inline in the content pane."
	| element |
	aDocObject ifNil: [ ^ self ].
	element := (GtPhlowTool default object: aDocObject)
		asElementDo: [ :e | e matchParent ].
	content removeChildren.
	content addChild: element
]

{ #category : 'as yet unclassified' }
ElixirCoderBrowser >> groupModulesByNamespace: moduleInfo [
	"I group modules by their dotted namespace, returning a tree of nodes."
	| groups entries |
	entries := moduleInfo collect: [ :each |
		| name parts |
		name := (each attributeAt: #name) asString.
		parts := $. split: (name copyReplaceAll: 'Elixir.' with: '').
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
