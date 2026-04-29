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

{ #category : 'private' }
ElixirApplicationAnalysis >> buildTreeNode: aLabel from: entries [
	"I build a tree node by consuming the namespace path.
	 entries is a list of {info, remainingParts} pairs.
	 A single leaf at this level merges its module info into the branch
	 node itself; multiple leaves become separate child leaf nodes."
	| leaves branches groups info leafChildren branchChildren |
	leaves := entries select: [ :e | e second isEmpty ].
	branches := entries reject: [ :e | e second isEmpty ].
	groups := branches groupedBy: [ :e | e second first ].
	info := leaves size = 1
		ifTrue: [ self moduleInfoEntriesFor: leaves first first ]
		ifFalse: [ { #module -> nil. #functions -> nil. #has_doc -> nil } ].
	leafChildren := leaves size > 1
		ifTrue: [ leaves collect: [ :e | self leafNodeFor: e first ] ]
		ifFalse: [ #() ].
	branchChildren := groups keys sorted collect: [ :k |
		self buildTreeNode: k
			from: ((groups at: k) collect: [ :e | { e first. e second allButFirst } ]) ].
	^ ({
		#label -> aLabel.
		#children -> (leafChildren , branchChildren) asArray }
		, info) asDictionary
]

{ #category : 'private' }
ElixirApplicationAnalysis >> compileDepsViewLabeled: aLabel query: aQuery appModules: appModules [
	"I build a single mondrian compile-deps sub-view."
	^ GtPhlowEmptyView new mondrian
		title: aLabel;
		painting: [ :aMondrian |
			| edges |
			edges := [ (self application evaluateAndWait: aQuery) asList ]
				on: Error do: [ #() ].
			BeamMondrianHelpers
				compileDepsOn: aMondrian
				edges: edges
				highlightModules: appModules
				application: self application ]
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> description [
	^ description
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> description: aDescription [
	description := aDescription
]

{ #category : 'gt-actions' }
ElixirApplicationAnalysis >> gtActionSystemOverviewFor: anAction [
	<gtAction>
	^ anAction button
		icon: BrGlamorousVectorIcons hierarchy;
		label: 'System Overview';
		action: [ :aButton | aButton phlow spawnObject: systemAnalysis ]
]

{ #category : 'gt-views' }
ElixirApplicationAnalysis >> gtCompileDepsFor: aView [
	<gtView>
	<gtBeamView>
	"I show compile-time dependency edges with sub-tabs for
	 app-only (internal deps) and full (including external).
	 App modules are blue, external deps are light gray."
	| appModules edges |
	edges := [ (self application evaluateAndWait:
		'GtBridge.HotReload.compile_dep_edges(app: ', self name resolve, ')') asList ]
		on: Error do: [ #() ].
	edges isEmpty ifTrue: [ ^ aView empty ].
	appModules := [ (self modules asList collect: [ :m | m symbol asString ]) asSet ]
		on: Error do: [ Set new ].
	^ aView composite
		title: 'Compile deps';
		priority: 22;
		views: {
			self compileDepsViewLabeled: 'Internal'
				query: 'GtBridge.HotReload.compile_dep_edges(app: ', self name resolve, ', internal: true)'
				appModules: appModules.
			self compileDepsViewLabeled: 'All'
				query: 'GtBridge.HotReload.compile_dep_edges(app: ', self name resolve, ')'
				appModules: appModules }
]

{ #category : 'gt-views' }
ElixirApplicationAnalysis >> gtDependencyGraphFor: aView [
	<gtView>
	<gtBeamView>
	^ aView mondrian
		title: 'Dependencies';
		priority: 20;
		painting: [ :aMondrian |
			BeamMondrianHelpers
				appDepGraphOn: aMondrian
				trees: { self application evaluateAndWait:
					'GtBridge.DepGraph.app_dep_tree(', self name resolve, ')' }
				apps: systemAnalysis appsByName
				color: (Color fromHexString: '#e8f0fe') ]
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> gtDisplayOn: aStream [
	aStream nextPutAll: self name asString
]

{ #category : 'gt-views' }
ElixirApplicationAnalysis >> gtDocCoverageFor: aView [
	<gtView>
	<gtBeamView>
	^ aView mondrian
		title: 'Doc coverage';
		priority: 18;
		painting: [ :mondrian |
			| dataByMod |
			dataByMod := ((self application evaluateAndWait:
				'GtBridge.Analysis.app_doc_coverage(', self name resolve, ')') asList
					collect: [ :data | (data attributeAt: #module) asString -> data ]) asDictionary.
			mondrian nodes
				shape: [ :modName |
					| data hasMod borderColor parts |
					data := dataByMod at: modName.
					hasMod := data attributeAt: #has_mod_doc.
					borderColor := hasMod
						ifTrue: [ Color fromHexString: '#2d8659' ]
						ifFalse: [ Color fromHexString: '#cc3333' ].
					parts := $. split: (modName copyReplaceAll: 'Elixir.' with: '').
					BrVerticalPane new
						alignTopCenter;
						fitContent;
						border: (BlBorder paint: borderColor width: 2);
						padding: (BlInsets left: 1 right: 1);
						margin: (BlInsets all: 3);
						addEventHandlerOn: BlClickEvent do: [ :evt |
							evt consumed: true.
							evt currentTarget phlow spawnObject:
								(self application evaluateAndWait:
									'GtBridge.Documentation.for_module(', modName, ')') ];
						addChildren: {
							BlTextElement new
								text: ('.' join: (parts last: (2 min: parts size))) asRopedText glamorousRegularSmallSize;
								constraintsDo: [ :c |
									c horizontal fitContent.
									c vertical fitContent ].
							BlElement new
								in: [ :e | e graph beChildrenContainer: #default ];
								constraintsDo: [ :c | c margin: (BlInsets all: 3) ] } ];
				with: dataByMod keys sorted;
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
ElixirApplicationAnalysis >> gtModuleTreeFor: aView [
	<gtView>
	<gtBeamView>
	"I show a Pharo-style system browser scoped to this application:
	 module namespace tree on the left with function counts and doc
	 status columns, module coder on the right that swaps to show the
	 selected module. Replaces the previous columned-tree-only view —
	 the browser is a superset that adds the inline coder pane."
	^ aView explicit
		title: 'Module tree';
		priority: 6;
		stencil: [ ElixirCoderBrowser forApplicationAnalysis: self ]
]

{ #category : 'gt-views' }
ElixirApplicationAnalysis >> gtOverviewFor: aView [
	<gtView>
	<gtBeamView>
	^ aView columnedList
		title: 'Overview';
		priority: 5;
		items: [ {
			{ 'Name'. self name asString }.
			{ 'Description'. self description asString }.
			{ 'Version'. self version asString }.
			{ 'Modules'. self modules }.
			{ 'Connected system'. systemAnalysis } } ];
		column: 'Property' text: #first;
		column: 'Value' text: #second;
		send: #second
]

{ #category : 'gt-views' }
ElixirApplicationAnalysis >> gtProblemsFor: aView [
	<gtView>
	<gtBeamView>
	^ aView columnedList
		title: 'Problems';
		priority: 12;
		items: [ self moduleInfo asList flatCollect: [ :each |
			| modName rows |
			modName := each attributeAt: #name.
			rows := OrderedCollection new.
			(each attributeAt: #has_doc) ifFalse: [
				rows add: { modName. 'Missing @moduledoc' } ].
			(each attributeAt: #source) ifFalse: [
				rows add: { modName. 'No source path' } ].
			rows ] ];
		column: 'Module' text: [ :each |
			each first copyReplaceAll: 'Elixir.' with: '' ];
		column: 'Issue' text: [ :each | each second ];
		send: [ :each |
			self application evaluateAndWait:
				'GtBridge.Documentation.for_module(', each first, ')' ]
]

{ #category : 'gt-views' }
ElixirApplicationAnalysis >> gtReverseDepsFor: aView [
	<gtView>
	<gtBeamView>
	^ aView mondrian
		title: 'Dependents';
		priority: 21;
		painting: [ :aMondrian |
			BeamMondrianHelpers
				appDepGraphOn: aMondrian
				trees: { self application evaluateAndWait:
					'GtBridge.DepGraph.app_reverse_dep_tree(', self name resolve, ')' }
				apps: systemAnalysis appsByName
				color: (Color fromHexString: '#f0e8fe') ]
]

{ #category : 'gt-search' }
ElixirApplicationAnalysis >> gtSearchFunctionsFor: aSearch [
	<gtSearch>
	| docForFn |
	docForFn := [ :f |
		self application evaluateAndWait:
			'GtBridge.Documentation.for_function(',
			(f attributeAt: #module), ', :',
			(f attributeAt: #name), ', ',
			(f attributeAt: #arity) asString, ')' ].
	^ aSearch explicit
		title: 'Functions';
		priority: 20;
		search: [ :ctx |
			| query |
			query := ctx searchQuery.
			(self application evaluateAndWait:
				'GtBridge.Analysis.search_functions(', self name resolve, ', "',
				(query copyReplaceAll: '"' with: '\"'), '")') asList ];
		itemName: [ :f |
			((f attributeAt: #module) copyReplaceAll: 'Elixir.' with: ''),
			'.', (f attributeAt: #name), '/', (f attributeAt: #arity) asString ];
		previewObject: docForFn;
		send: docForFn
]

{ #category : 'gt-search' }
ElixirApplicationAnalysis >> gtSearchModulesFor: aSearch [
	<gtSearch>
	^ aSearch list
		title: 'Modules';
		priority: 10;
		items: [ (self modules asList collect: [ :m | m symbol asString ]) sorted ];
		itemName: [ :modName | modName copyReplaceAll: 'Elixir.' with: '' ];
		filterBySubstring;
		send: [ :modName |
			self application evaluateAndWait:
				'GtBridge.Documentation.for_module(', modName, ')' ]
]

{ #category : 'gt-views' }
ElixirApplicationAnalysis >> gtSupervisionTreeFor: aView [
	<gtView>
	<gtBeamView>
	| supPid |
	supPid := [ self application evaluateAndWait:
		'case Application.spec(', self name resolve, ', :mod) do
			{mod, _} ->
				Process.whereis(Module.concat(mod, Supervisor))
				|| Process.whereis(mod)
				|| (case :application_controller.get_master(', self name resolve, ') do
					pid when is_pid(pid) -> elem(:application_master.get_child(pid), 0)
					_ -> nil
				end)
			_ -> nil
		end' ]
		on: Error do: [ nil ].
	(supPid isNil or: [ supPid isKindOf: BeamBridgeEvalError ]) ifTrue: [ ^ aView empty ].
	^ supPid gtSupervisionView: aView
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

{ #category : 'private' }
ElixirApplicationAnalysis >> leafNodeFor: aModuleInfo [
	"I return a leaf tree node dictionary for a fully-qualified module."
	| parts |
	parts := $. split: ((aModuleInfo attributeAt: #name) copyReplaceAll: 'Elixir.' with: '').
	^ ({
		#label -> parts last.
		#children -> #() }
		, (self moduleInfoEntriesFor: aModuleInfo)) asDictionary
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> moduleInfo [
	"I return per-module metadata from the BEAM for the modules view."
	^ self application evaluateAndWait:
		'GtBridge.Analysis.module_details(', self name resolve, ')'
]

{ #category : 'private' }
ElixirApplicationAnalysis >> moduleInfoEntriesFor: aModuleInfo [
	"I return the module/functions/has_doc associations from a module info object.
	 Used to merge a single leaf's metadata into its parent branch node."
	^ {
		#module -> (aModuleInfo attributeAt: #name).
		#functions -> (aModuleInfo attributeAt: #functions).
		#has_doc -> (aModuleInfo attributeAt: #has_doc) }
]

{ #category : 'accessing' }
ElixirApplicationAnalysis >> moduleTreeRoots [
	"I return a tree of module info grouped by namespace prefix."
	| entries groups |
	entries := self moduleInfo asList collect: [ :each |
		{ each. ($. split: ((each attributeAt: #name) copyReplaceAll: 'Elixir.' with: '')) } ].
	groups := entries groupedBy: [ :e | e second first ].
	^ (groups keys sorted collect: [ :key |
		self buildTreeNode: key
			from: ((groups at: key) collect: [ :e | { e first. e second allButFirst } ]) ]) asArray
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
