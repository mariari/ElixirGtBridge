Class {
	#name : 'ElixirSystemAnalysis',
	#superclass : 'Object',
	#instVars : [
		'application',
		'gitRepository',
		'applications'
	],
	#category : 'Gt4beam-Analysis',
	#package : 'Gt4beam',
	#tag : 'Analysis'
}

{ #category : 'instance creation' }
ElixirSystemAnalysis class >> onApplication: aBeamLinkApplication [
	^ self new
		application: aBeamLinkApplication;
		yourself
]

{ #category : 'instance creation' }
ElixirSystemAnalysis class >> onApplication: aBeamLinkApplication gitRepository: aGtGitRepository [
	^ self new
		application: aBeamLinkApplication;
		gitRepository: aGtGitRepository;
		yourself
]

{ #category : 'accessing' }
ElixirSystemAnalysis >> application [
	^ application
]

{ #category : 'accessing' }
ElixirSystemAnalysis >> application: anApplication [
	application := anApplication
]

{ #category : 'accessing' }
ElixirSystemAnalysis >> applications [
	^ applications ifNil: [
		applications := self loadedApplicationTuples asList collect: [ :each |
			ElixirApplicationAnalysis on: each system: self ] ]
]

{ #category : 'accessing' }
ElixirSystemAnalysis >> appsByName [
	"I return a dict mapping app name strings to ElixirApplicationAnalysis
	 for dep-graph clickthrough lookups."
	^ (self applications collect: [ :app | app name symbol asString -> app ]) asDictionary
]

{ #category : 'accessing' }
ElixirSystemAnalysis >> gitRepository [
	^ gitRepository
]

{ #category : 'accessing' }
ElixirSystemAnalysis >> gitRepository: aGitRepository [
	gitRepository := aGitRepository
]

{ #category : 'gt views' }
ElixirSystemAnalysis >> gtAppDependenciesFor: aView [
	<gtView>
	^ aView mondrian
		title: 'App dependencies';
		priority: 15;
		painting: [ :aMondrian |
			BeamMondrianHelpers
				appDepGraphOn: aMondrian
				trees: (self application evaluateAndWait:
					'Enum.map(GtBridge.Analysis.root_apps(), fn r -> GtBridge.Analysis.app_dep_tree(r) end)') asList
				apps: self appsByName
				color: (Color fromHexString: '#e8f0fe') ]
]

{ #category : 'gt views' }
ElixirSystemAnalysis >> gtApplicationsFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Applications';
		priority: 10;
		items: [ self applications sorted: [ :a :b | a name asString < b name asString ] ];
		column: 'Name' text: [ :each | each name asString ] weight: 2;
		column: 'Version' text: [ :each | each version asString ];
		send: [ :each | each ]
]

{ #category : 'gt views' }
ElixirSystemAnalysis >> gtDashboardFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Dashboard';
		priority: 3;
		items: [ | stats |
			stats := self application evaluateAndWait: 'GtBridge.Analysis.system_stats()'.
			{
			{ 'Applications'. stats attributeAt: #apps }.
			{ 'Total modules'. stats attributeAt: #modules }.
			{ 'Total functions'. stats attributeAt: #functions }.
			{ 'Modules with docs'. (stats attributeAt: #with_docs) asString, ' / ', (stats attributeAt: #modules) asString }.
			{ 'Modules with source'. (stats attributeAt: #with_source) asString, ' / ', (stats attributeAt: #modules) asString } } ];
		column: 'Metric' text: #first;
		column: 'Value' text: [ :each | each second asString ]
]

{ #category : 'gt views' }
ElixirSystemAnalysis >> gtDocCoverageFor: aView [
	"I show documentation coverage per application as a nested heatmap."
	<gtView>
	^ aView mondrian
		title: 'Doc coverage';
		priority: 8;
		painting: [ :mondrian |
			| dataByApp |
			dataByApp := ((self application evaluateAndWait:
				'GtBridge.Analysis.system_doc_coverage()') asList
					collect: [ :data | (data attributeAt: #app) asString -> data ]) asDictionary.
			mondrian nodes
				shape: [ :app |
					| appName |
					appName := app name symbol asString.
					BrVerticalPane new
						alignTopCenter;
						fitContent;
						border: (BlBorder paint: Color gray width: 1);
						padding: (BlInsets left: 1 right: 1);
						margin: (BlInsets all: 3);
						addEventHandlerOn: BlClickEvent do: [ :evt |
							evt consumed: true.
							evt currentTarget phlow spawnObject: app ];
						addChildren: {
							BlTextElement new
								text: appName asRopedText glamorousRegularSmallSize;
								constraintsDo: [ :c |
									c horizontal fitContent.
									c vertical fitContent ].
							BlElement new
								in: [ :e | e graph beChildrenContainer: #default ];
								border: Color black;
								constraintsDo: [ :c | c margin: (BlInsets all: 5) ] } ];
				with: (self applications select: [ :app | dataByApp includesKey: app name symbol asString ]);
				forEach: [ :app |
					| data |
					data := dataByApp at: app name symbol asString.
					mondrian nodes
						stencil: [ :m |
							| color modName |
							modName := (m attributeAt: #name) asString.
							color := (m attributeAt: #has_doc)
								ifTrue: [ Color fromHexString: '#a8d5a2' ]
								ifFalse: [ Color fromHexString: '#ff453b' ].
							BlElement new
								size: 8 @ 8;
								background: color;
								border: (BlBorder paint: color darker width: 1);
								addEventHandlerOn: BlClickEvent do: [ :evt |
									evt consumed: true.
									evt currentTarget phlow spawnObject:
										(self application evaluateAndWait:
											'GtBridge.Documentation.for_module(', modName, ')') ] ];
						with: (data attributeAt: #modules) asList.
					mondrian layout grid cellSpacing: 2 ].
			mondrian layout rectanglePack ]
]

{ #category : 'gt views' }
ElixirSystemAnalysis >> gtMnesiaTablesFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Mnesia tables';
		priority: 25;
		items: [ (self application evaluateAndWait:
			'GtBridge.Analysis.mnesia_tables()') asList ];
		column: 'Table' text: [ :each | each attributeAt: #name ] weight: 2;
		column: 'Type' text: [ :each | each attributeAt: #type ] width: 50;
		column: 'Size' text: [ :each | (each attributeAt: #size) asString ] width: 50;
		column: 'Attributes' text: [ :each | each attributeAt: #attrs ];
		send: [ :each |
			MnesiaTableInspector new
				tableName: (each attributeAt: #name);
				application: self application ]
]

{ #category : 'gt views' }
ElixirSystemAnalysis >> gtOverviewFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Overview';
		priority: 5;
		items: [ | info |
			info := [ self application evaluateAndWait:
				'GtBridge.Analysis.system_info()' ]
				on: Error do: [ nil ].
			info ifNil: [ { { 'Connected'. false } } ]
				ifNotNil: [
			{
			{ 'Connected'. true }.
			{ 'Node'. (info attributeAt: #node) asString }.
			{ 'Elixir'. (info attributeAt: #elixir) asString }.
			{ 'OTP'. (info attributeAt: #otp) asString }.
			{ 'Working directory'. (info attributeAt: #cwd) asString }.
			{ 'Schedulers'. info attributeAt: #schedulers }.
			{ 'Processes'. info attributeAt: #processes }.
			{ 'Memory (MB)'. info attributeAt: #memory_mb }.
			{ 'Applications'. self applications size } } ] ];
		column: 'Property' text: #first;
		column: 'Value' text: [ :each | each second asString ]
]

{ #category : 'gt views' }
ElixirSystemAnalysis >> gtProblemsFor: aView [
	"I show undocumented modules across all applications."
	<gtView>
	^ aView columnedList
		title: 'Problems';
		priority: 12;
		items: [ self applications flatCollect: [ :app |
			| moduleInfo |
			moduleInfo := [ app moduleInfo asList ] on: Error do: [ #() ].
			moduleInfo flatCollect: [ :m | self problemsFor: m in: app ] ] ];
		column: 'Module' text: [ :each |
			each first copyReplaceAll: 'Elixir.' with: '' ] weight: 2;
		column: 'Application' text: [ :each | each second ];
		column: 'Issue' text: [ :each | each third ];
		send: [ :each |
			self application evaluateAndWait:
				'GtBridge.Documentation.for_module(', each first, ')' ]
]

{ #category : 'testing' }
ElixirSystemAnalysis >> hasApplication [
	^ application isNotNil
]

{ #category : 'testing' }
ElixirSystemAnalysis >> hasGitRepository [
	^ gitRepository isNotNil
]

{ #category : 'testing' }
ElixirSystemAnalysis >> isConnected [
	^ self hasApplication and: [ application isRunning ]
]

{ #category : 'accessing' }
ElixirSystemAnalysis >> loadedApplicationRecords [
	^ self loadedApplicationTuples asList collect: [ :each |
		{ each itemAt: 0. each itemAt: 1. each itemAt: 2 } ]
]

{ #category : 'accessing' }
ElixirSystemAnalysis >> loadedApplicationTuples [
	^ self isConnected
		ifTrue: [ self remoteApplications ]
		ifFalse: [ #() ]
]

{ #category : 'printing' }
ElixirSystemAnalysis >> printOn: aStream [
	aStream
		nextPutAll: 'ElixirSystemAnalysis';
		nextPutAll: '(';
		nextPutAll: (self hasApplication
			ifTrue: [ application class name ]
			ifFalse: [ 'no application' ]);
		nextPut: $)
]

{ #category : 'private' }
ElixirSystemAnalysis >> problemsFor: moduleInfo in: anApp [
	"I return the problem triples {modName. appName. issue} for a single
	 module info dict — empty if the module has no problems. Shared by
	 the Problems view's flatCollect chain."
	| modName appName rows |
	modName := moduleInfo attributeAt: #name.
	appName := anApp name asString.
	rows := OrderedCollection new.
	(moduleInfo attributeAt: #has_doc) ifFalse: [
		rows add: { modName. appName. 'Missing @moduledoc' } ].
	(moduleInfo attributeAt: #source) ifFalse: [
		rows add: { modName. appName. 'No source path' } ].
	^ rows
]

{ #category : 'accessing' }
ElixirSystemAnalysis >> remoteApplications [
	^ self application
		evaluateAndWait: 'Application.loaded_applications()'
]

{ #category : 'accessing' }
ElixirSystemAnalysis >> workingDirectory [
	^ self hasApplication
		ifTrue: [ application workingDirectory ]
		ifFalse: [ nil ]
]
