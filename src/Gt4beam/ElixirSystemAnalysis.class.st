Class {
	#name : 'ElixirSystemAnalysis',
	#superclass : 'Object',
	#instVars : [
		'application',
		'gitRepository'
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
	^ self loadedApplicationTuples asList collect: [ :each |
		ElixirApplicationAnalysis on: each system: self ]
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
			| edgeData edges nodes appsByName |
			edgeData := self application newCommandFactory << '
  loaded = Application.loaded_applications() |> Enum.map(fn {a, _, _} -> a end) |> MapSet.new()
  skip = MapSet.new([:kernel, :stdlib, :elixir, :compiler, :logger])
  Application.loaded_applications()
  |> Enum.flat_map(fn {app, _, _} ->
    deps = Application.spec(app, :applications) || []
    Enum.filter(deps, fn dep -> MapSet.member?(loaded, dep) and not MapSet.member?(skip, dep) end)
    |> Enum.map(fn dep -> {Atom.to_string(app), Atom.to_string(dep)} end)
  end)'; sendAndWait.
			edges := edgeData asList collect: [ :pair |
				(pair itemAt: 0) -> (pair itemAt: 1) ].
			nodes := ((edges collect: #key) , (edges collect: #value)) asSet asArray.
			appsByName := Dictionary new.
			self applications do: [ :app |
				appsByName at: (app name symbol asString) put: app ].
			aMondrian nodes
				stencil: [ :name |
					BeamMondrianHelpers
						nodeLabeled: name
						color: (Color fromHexString: '#e8f0fe')
						onClick: [ :evt |
							evt target phlow spawnObject:
								(appsByName at: name ifAbsent: [ name ]) ] ];
				with: nodes.
			aMondrian edges stencil: [ BeamMondrianHelpers edgeStencil ];
				connectToAll: [ :name |
					(edges select: [ :e | e key = name ]) collect: #value ].
			aMondrian layout force charge: -500; length: 100 ]
]

{ #category : 'gt views' }
ElixirSystemAnalysis >> gtApplicationsFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Applications';
		priority: 10;
		items: [ self applications ];
		column: 'Name' text: [ :each | each name asString ] weight: 2;
		column: 'Version' text: [ :each | each version asString ];
		column: 'Modules' text: [ :each |
			[ each modules asList size asString ] on: Error do: [ '?' ] ] width: 60;
		column: 'Docs' text: [ :each |
			[ | info docsCount |
			info := each moduleInfo asList.
			docsCount := (info count: [ :m | m attributeAt: #has_doc ]).
			docsCount asString, '/', info size asString ]
			on: Error do: [ '?' ] ] width: 70;
		send: [ :each | each ]
]

{ #category : 'gt views' }
ElixirSystemAnalysis >> gtDocCoverageFor: aView [
	"I show documentation coverage per application as a nested heatmap."
	<gtView>
	^ aView mondrian
		title: 'Doc coverage';
		priority: 8;
		painting: [ :mondrian |
			| rawData dataByApp apps |
			rawData := (self application evaluateAndWait:
				'GtBridge.Analysis.system_doc_coverage()') asList.
			apps := self applications.
			dataByApp := Dictionary new.
			rawData do: [ :data |
				dataByApp at: (data attributeAt: #app) asString put: data ].
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
						addChildren: {
							BrLabel new
								aptitude: (BrGlamorousLabelAptitude new fontSize: 10);
								text: appName.
							BlElement new
								in: [ :e | e graph beChildrenContainer: #default ];
								border: Color black;
								constraintsDo: [ :c | c margin: (BlInsets all: 5) ] } ];
				with: (apps select: [ :app | dataByApp includesKey: app name symbol asString ]);
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
ElixirSystemAnalysis >> gtProblemsFor: aView [
	"I show undocumented modules across all applications."
	<gtView>
	^ aView columnedList
		title: 'Problems';
		priority: 12;
		items: [ | problems |
			problems := OrderedCollection new.
			self applications do: [ :app |
				[ app moduleInfo asList do: [ :m |
					| name |
					name := m attributeAt: #name.
					(m attributeAt: #has_doc) ifFalse: [
						problems add: { name. app name asString. 'Missing @moduledoc' } ].
					(m attributeAt: #source) ifFalse: [
						problems add: { name. app name asString. 'No source path' } ] ] ]
				on: Error do: [ "skip" ] ].
			problems ];
		column: 'Module' text: [ :each |
			each first copyReplaceAll: 'Elixir.' with: '' ] weight: 2;
		column: 'Application' text: [ :each | each second ];
		column: 'Issue' text: [ :each | each third ];
		send: [ :each |
			self application evaluateAndWait:
				'GtBridge.Documentation.for_module(', each first, ')' ]
]

{ #category : 'gt views' }
ElixirSystemAnalysis >> gtMnesiaTablesFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Mnesia tables';
		priority: 25;
		items: [ (self application evaluateAndWait:
			':mnesia.system_info(:tables)
			|> Enum.reject(fn t -> t == :schema end)
			|> Enum.map(fn t ->
				%{name: Atom.to_string(t),
				  size: :mnesia.table_info(t, :size),
				  type: Atom.to_string(:mnesia.table_info(t, :type)),
				  attrs: :mnesia.table_info(t, :attributes) |> Enum.map(fn a -> Atom.to_string(a) end) |> Enum.join(", ")}
			end)
			|> Enum.sort_by(fn t -> t.name end)') asList ];
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
ElixirSystemAnalysis >> gtOverviewFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Overview';
		priority: 5;
		items: [ {
			{ 'Connected'. self isConnected }.
			{ 'Working directory'. self workingDirectory ifNil: [ 'n/a' ] }.
			{ 'Git repository'. self gitRepository ifNil: [ 'n/a' ] }.
			{ 'Loaded applications'. self loadedApplicationRecords size } } ];
		column: 'Property' text: #first;
		column: 'Value' text: #second;
		send: #second
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
