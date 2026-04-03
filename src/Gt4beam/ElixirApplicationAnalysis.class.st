Class {
	#name : 'ElixirApplicationAnalysis',
	#superclass : 'Object',
	#instVars : [
		'systemAnalysis',
		'name',
		'description',
		'version',
		'tuple'
	],
	#category : 'Gt4beam-Analysis',
	#package : 'Gt4beam',
	#tag : 'Analysis'
}

{ #category : 'instance creation' }
ElixirApplicationAnalysis class >> on: aTuple system: anElixirSystemAnalysis [
	^ self new
		systemAnalysis: anElixirSystemAnalysis;
		tuple: aTuple;
		name: (aTuple itemAt: 0);
		description: (aTuple itemAt: 1);
		version: (aTuple itemAt: 2);
		yourself
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> application [
	^ systemAnalysis application
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> description [
	^ description
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> description: aDescription [
	description := aDescription
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> gtDisplayOn: aStream [
	aStream nextPutAll: self name asString
]

{ #category : 'gt-views' }
ElixirApplicationAnalysis >> gtDependencyGraphFor: aView [
	<gtView>
	^ aView mondrian
		title: 'Dependencies';
		priority: 20;
		painting: [ :aMondrian |
			| edgeData nodes edges app |
			app := self application.
			edgeData := app newCommandFactory
				<< ('GtBridge.Analysis.module_graph(', self name resolve, ')
  |> Enum.filter(fn {from, to} ->
    Application.get_application(from) == ', self name resolve, '
    and Application.get_application(to) == ', self name resolve, '
  end)
  |> Enum.map(fn {from, to} -> {inspect(from), inspect(to)} end)');
				sendAndWait.
			edges := edgeData asList collect: [ :pair |
				(pair itemAt: 0) asString -> (pair itemAt: 1) asString ].
			nodes := ((edges collect: #key) , (edges collect: #value)) asSet asArray.
			aMondrian nodes
				stencil: [ :name |
					| el |
					el := BeamMondrianHelpers
						nodeLabeled: (name copyReplaceAll: 'Elixir.' with: '')
						color: (Color fromHexString: '#e8f0fe')
						onClick: [ :evt | ].
					el addEventHandlerOn: BlClickEvent do: [ :evt |
						evt consumed: true.
						evt currentTarget phlow spawnObject:
							(app newCommandFactory
								<< ('GtBridge.Documentation.for_module(', name, ')');
								sendAndWait) ].
					el ];
				with: nodes.
			aMondrian edges stencil: [ BeamMondrianHelpers edgeStencil ];
				connectToAll: [ :name |
					(edges select: [ :e | e key = name ]) collect: #value ].
			aMondrian layout horizontalTree ]
]

{ #category : 'gt-views' }
ElixirApplicationAnalysis >> gtDocCoverageFor: aView [
	<gtView>
	^ aView mondrian
		title: 'Doc coverage';
		priority: 18;
		painting: [ :mondrian |
			| rawData dataByMod modNames |
			rawData := (self application evaluateAndWait:
				'GtBridge.Analysis.app_doc_coverage(', self name resolve, ')') asList.
			dataByMod := Dictionary new.
			rawData do: [ :data |
				dataByMod at: (data attributeAt: #module) asString put: data ].
			modNames := dataByMod keys sorted.
			mondrian nodes
				shape: [ :modName |
					| data hasMod borderColor |
					data := dataByMod at: modName.
					hasMod := data attributeAt: #has_mod_doc.
					borderColor := hasMod
						ifTrue: [ Color fromHexString: '#2d8659' ]
						ifFalse: [ Color fromHexString: '#cc3333' ].
					BrVerticalPane new
						alignTopCenter;
						fitContent;
						border: (BlBorder paint: borderColor width: 2);
						padding: (BlInsets left: 1 right: 1);
						margin: (BlInsets all: 3);
						when: BlClickEvent do: [ :evt |
							evt target phlow spawnObject:
								(self application evaluateAndWait:
									'GtBridge.Documentation.for_module(', modName, ')') ];
						addChildren: {
							BrLabel new
								aptitude: (BrGlamorousLabelAptitude new fontSize: 9);
								text: (modName copyReplaceAll: 'Elixir.' with: '').
							BlElement new
								in: [ :e | e graph beChildrenContainer: #default ];
								constraintsDo: [ :c | c margin: (BlInsets all: 3) ] } ];
				with: modNames;
				forEach: [ :modName |
					| data |
					data := dataByMod at: modName.
					mondrian nodes
						stencil: [ :f |
							| color fnName fnArity |
							fnName := (f attributeAt: #name) asString.
							fnArity := (f attributeAt: #arity) asString.
							color := (f attributeAt: #has_doc)
								ifTrue: [ Color fromHexString: '#a8d5a2' ]
								ifFalse: [ Color fromHexString: '#ff453b' ].
							BlElement new
								size: 10 @ 10;
								background: color;
								border: (BlBorder paint: color darker width: 1);
								addEventHandlerOn: BlClickEvent do: [ :evt |
									evt consumed: true.
									evt currentTarget phlow spawnObject:
										(self application evaluateAndWait:
											'GtBridge.Documentation.for_function(', modName, ', :', fnName, ', ', fnArity, ')') ] ];
						with: (data attributeAt: #functions) asList.
					mondrian layout grid cellSpacing: 1 ].
			mondrian layout rectanglePack ]
]

{ #category : 'gt-views' }
ElixirApplicationAnalysis >> gtSupervisionTreeFor: aView [
	<gtView>
	| supPid |
	supPid := [ self application evaluateAndWait:
		'case Application.spec(', self name resolve, ', :mod) do
			{mod, _} -> Process.whereis(Module.concat(mod, Supervisor)) || Process.whereis(mod)
			_ -> nil
		end' ]
		on: Error do: [ nil ].
	(supPid isNil or: [ supPid isKindOf: BeamBridgeEvalError ]) ifTrue: [ ^ aView empty ].
	^ aView mondrian
		title: 'Supervision';
		priority: 22;
		painting: [ :aMondrian |
			| tree |
			tree := self application evaluateAndWait:
				'GtBridge.Analysis.supervision_tree(', supPid resolve, ')'.
			BeamMondrianHelpers
				supervisionTreeOn: aMondrian from: tree poolThreshold: 12 ]
]

{ #category : 'gt-views' }
ElixirApplicationAnalysis >> gtCapabilitySummaryFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Capability summary';
		priority: 8;
		items: [ {
			{ 'Modules'. self modules asList size } } ];
		column: 'Capability' text: #first;
		column: 'Value' text: [ :each | each second asString ]
]

{ #category : 'gt-views' }
ElixirApplicationAnalysis >> gtProblemsFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Problems';
		priority: 12;
		items: [ | info problems |
			info := self moduleInfo asList.
			problems := OrderedCollection new.
			info do: [ :each |
				| name |
				name := each attributeAt: #name.
				(each attributeAt: #has_doc)
					ifFalse: [ problems add: { name. 'Missing @moduledoc' } ].
				(each attributeAt: #source)
					ifFalse: [ problems add: { name. 'No source path' } ] ].
			problems ];
		column: 'Module' text: [ :each |
			each first copyReplaceAll: 'Elixir.' with: '' ];
		column: 'Issue' text: [ :each | each second ];
		send: [ :each |
			self application evaluateAndWait:
				'GtBridge.Documentation.for_module(', each first, ')' ]
]

{ #category : 'gt-views' }
ElixirApplicationAnalysis >> gtModulesFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Modules';
		priority: 15;
		items: [ self moduleInfo asList ];
		column: 'Module' text: [ :each |
			((each attributeAt: #name) copyReplaceAll: 'Elixir.' with: '') ];
		column: 'Type' text: [ :each |
			(each attributeAt: #elixir)
				ifTrue: [ 'Elixir' ] ifFalse: [ 'Erlang' ] ] width: 60;
		column: 'Fns' text: [ :each |
			(each attributeAt: #functions) asString ] width: 40;
		column: 'Docs' text: [ :each |
			(each attributeAt: #has_doc)
				ifTrue: [ '✓' ] ifFalse: [ '✗' ] ] width: 40;
		column: 'Source' text: [ :each |
			(each attributeAt: #source)
				ifTrue: [ '✓' ] ifFalse: [ '✗' ] ] width: 50;
		send: [ :each |
			self application evaluateAndWait:
				'GtBridge.Documentation.for_module(', (each attributeAt: #name), ')' ]
]

{ #category : 'gt-views' }
ElixirApplicationAnalysis >> gtModuleTreeFor: aView [
	<gtView>
	^ aView columnedTree
		title: 'Module tree';
		priority: 14;
		items: [ self moduleTreeRoots ];
		children: [ :node | node at: #children ];
		column: 'Name' text: [ :node | node at: #label ];
		column: 'Fns' text: [ :node |
			(node at: #module)
				ifNil: [ '' ]
				ifNotNil: [ (node at: #functions) asString ] ] width: 40;
		column: 'Docs' text: [ :node |
			(node at: #module)
				ifNil: [ '' ]
				ifNotNil: [ (node at: #has_doc)
					ifTrue: [ '✓' ] ifFalse: [ '✗' ] ] ] width: 40;
		send: [ :node |
			(node at: #module)
				ifNotNil: [ :name |
					self application evaluateAndWait:
						'GtBridge.Documentation.for_module(', name, ')' ]
				ifNil: [ self ] ]
]

{ #category : 'gt-views' }
ElixirApplicationAnalysis >> gtOverviewFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Overview';
		priority: 5;
		items: [ {
			{ 'Name'. self name asString }.
			{ 'Description'. self description asString }.
			{ 'Version'. self version asString }.
			{ 'Modules'. self modules }.
			{ 'Tuple'. self tuple }.
			{ 'Connected system'. systemAnalysis } } ];
		column: 'Property' text: #first;
		column: 'Value' text: #second;
		send: #second
]

{ #category : 'gt views' }
ElixirApplicationAnalysis >> gtTupleFor: aView [
	<gtView>
	| tupleObject |
	tupleObject := self tuple.
	tupleObject ifNil: [ ^ aView empty ].
	^ aView composite
		title: 'Tuple';
		priority: 10;
		views: tupleObject gtViewsInCurrentContext
]

{ #category : 'testing' }
ElixirApplicationAnalysis >> hasModules [
	^ [ self modules isNotNil ]
		on: Error
		do: [ false ]
]

{ #category : 'testing' }
ElixirApplicationAnalysis >> hasTuple [
	^ tuple isNotNil
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> moduleInfo [
	"I return per-module metadata from the BEAM for the modules view."
	^ self application newCommandFactory
		<< ('
  mods = case :application.get_key(', self name resolve, ', :modules) do
    {:ok, m} -> m
    _ -> []
  end
  Enum.map(mods, fn mod ->
    name = inspect(mod)
    is_elixir = String.starts_with?(name, "Elixir.") or String.contains?(name, ".")
    {fun_count, has_doc} = case Code.fetch_docs(mod) do
      {:docs_v1, _, _, _, %{"en" => d}, _, docs} when d != "" ->
        {length(docs), true}
      {:docs_v1, _, _, _, _, _, docs} ->
        {length(docs), false}
      _ -> {0, false}
    end
    source = mod.module_info(:compile)[:source] != nil
    %{name: name, elixir: is_elixir, functions: fun_count,
      has_doc: has_doc, source: source}
  end)
  |> Enum.sort_by(fn m -> m.name end)');
		sendAndWait
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> moduleTreeRoots [
	"I return a tree of module info grouped by namespace prefix."
	| info groups |
	info := self moduleInfo asList.
	groups := Dictionary new.
	info do: [ :each |
		| name parts key |
		name := each attributeAt: #name.
		parts := $. split: (name copyReplaceAll: 'Elixir.' with: '').
		key := parts first.
		(groups at: key ifAbsentPut: [ OrderedCollection new ])
			add: { each. parts } ].
	^ (groups keys sorted collect: [ :key |
		self buildTreeNode: key from: (groups at: key) depth: 1 ]) asArray
]

{ #category : 'private' }
ElixirApplicationAnalysis >> buildTreeNode: label from: entries depth: depth [
	"I recursively build a tree node with children grouped by namespace."
	| leaves branches branchGroups node |
	leaves := entries select: [ :e | (e second size) = depth ].
	branches := entries reject: [ :e | (e second size) = depth ].
	branchGroups := Dictionary new.
	branches do: [ :e |
		| key |
		key := e second at: depth + 1.
		(branchGroups at: key ifAbsentPut: [ OrderedCollection new ]) add: e ].
	node := Dictionary new.
	node at: #label put: label.
	leaves size = 1
		ifTrue: [
			| info |
			info := leaves first first.
			node at: #module put: (info attributeAt: #name).
			node at: #functions put: (info attributeAt: #functions).
			node at: #has_doc put: (info attributeAt: #has_doc) ]
		ifFalse: [
			node at: #module put: nil.
			node at: #functions put: nil.
			node at: #has_doc put: nil ].
	node at: #children put: (
		((leaves size > 1
			ifTrue: [ leaves collect: [ :e |
				| info leaf |
				info := e first.
				leaf := Dictionary new.
				leaf at: #label put: e second last.
				leaf at: #module put: (info attributeAt: #name).
				leaf at: #functions put: (info attributeAt: #functions).
				leaf at: #has_doc put: (info attributeAt: #has_doc).
				leaf at: #children put: #().
				leaf ] ]
			ifFalse: [ #() ]) ,
		(branchGroups keys sorted collect: [ :k |
			self buildTreeNode: k from: (branchGroups at: k) depth: depth + 1 ])) asArray).
	^ node
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> modules [
	^ self application
		evaluateAndWait:
			'Application.spec(', self name resolve, ', :modules)'
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> name [
	^ name
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> name: aName [
	name := aName
]

{ #category : 'printing' }
ElixirApplicationAnalysis >> printOn: aStream [
	aStream
		nextPutAll: 'ElixirApplicationAnalysis(';
		nextPutAll: self name asString;
		nextPut: $)
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> systemAnalysis [
	^ systemAnalysis
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> systemAnalysis: anElixirSystemAnalysis [
	systemAnalysis := anElixirSystemAnalysis
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> tuple [
	^ tuple
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> tuple: aTuple [
	tuple := aTuple
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> version [
	^ version
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> version: aVersion [
	version := aVersion
]
