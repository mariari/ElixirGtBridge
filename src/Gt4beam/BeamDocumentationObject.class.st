Class {
	#name : 'BeamDocumentationObject',
	#superclass : 'BeamProxyObject',
	#category : 'Gt4beam-Documentation',
	#package : 'Gt4beam',
	#tag : 'Documentation'
}

{ #category : 'accessing' }
BeamDocumentationObject class >> elixirClass [
	^ 'GtBridge.Documentation'
]

{ #category : 'accessing' }
BeamDocumentationObject >> applicationAnalysis [
	"I return the ElixirApplicationAnalysis for my owning application."
	| appAtom sys |
	appAtom := self evaluateAndWait:
		'Application.get_application(elem(', self resolve, '.query, 1))'.
	appAtom ifNil: [ ^ nil ].
	sys := ElixirSystemAnalysis onApplication: self application.
	^ sys applications
		detect: [ :each | each name symbol = appAtom symbol ]
		ifNone: [ nil ]
]

{ #category : 'accessing' }
BeamDocumentationObject >> functionLines [
	"I return {startLine. endLine} for a function-scoped Documentation, or nil."
	| result |
	result := self
		evaluateAndWait:
			'GtBridge.Resolve.function_lines(' , self resolve , ')'.
	result ifNil: [ ^ nil ].
	^ { result itemAt: 0. result itemAt: 1 }
]

{ #category : 'accessing' }
BeamDocumentationObject >> functionTarget [
	"I return an ElixirFunctionScrollTarget for a function-scoped
	 Documentation, or nil for module-only docs.  Match by name+arity
	 so macro-generated entries (start: 0) land on the right row."
	| result |
	result := self evaluateAndWait:
		'case ', self resolve, '.query do
		   {:function, _, name, arity} -> {Atom.to_string(name), arity}
		   _ -> nil
		 end'.
	result ifNil: [ ^ nil ].
	^ ElixirFunctionScrollTarget new
		functionName: (result itemAt: 0) asString
		arity: (result itemAt: 1) asInteger
]

{ #category : 'gt-actions' }
BeamDocumentationObject >> gtActionApplicationFor: anAction [
	<gtAction>
	^ anAction button
		icon: BrGlamorousVectorIcons hierarchy;
		label: 'Application';
		action: [ :aButton |
			self applicationAnalysis ifNotNil: [ :app |
				aButton phlow spawnObject: app ] ]
]

{ #category : 'gt-views' }
BeamDocumentationObject >> gtApplicationFor: aView [
	<gtView>
	<gtBeamView>
	| appAnalysis |
	appAnalysis := self applicationAnalysis.
	appAnalysis ifNil: [ ^ aView empty ].
	^ aView forward
		title: 'Application';
		priority: 50;
		object: [ appAnalysis ];
		view: #gtOverviewFor:
]

{ #category : 'gt-views' }
BeamDocumentationObject >> gtCoderFor: aView [
	<gtView>
	<gtBeamView>
	"I show the module coder. Source file is optional — without it
	 the Functions/Source tabs hide but Help/Dependencies still work."
	| file modName |
	modName := [ self evaluateAndWait:
		'inspect(elem(', self resolve, '.query, 1))' ]
		on: Error do: [ nil ].
	modName isString ifFalse: [ ^ aView empty ].
	file := [ | f |
		f := self sourceFile.
		(f isString and: [ f asFileReference exists ])
			ifTrue: [ f ] ifFalse: [ nil ] ]
		on: Error do: [ nil ].
	^ aView explicit
		title: 'Coder';
		priority: 5;
		stencil: [
			| coder target lineRange |
			coder := ElixirModuleCoder new
				moduleName: modName;
				application: self application.
			file ifNotNil: [ coder sourcePath: file ].
			target := [ self functionTarget ] on: Error do: [ nil ].
			target
				ifNotNil: [ coder focusFunctionTarget: target ]
				ifNil: [
					lineRange := [ self functionLines ] on: Error do: [ nil ].
					lineRange ifNotNil: [ coder focusLine: lineRange ] ].
			coder asCoderViewModel asElement ]
]

{ #category : 'gt-views' }
BeamDocumentationObject >> gtDependenciesFor: aView [
	"I show a dependency graph. No <gtView> pragma — this is only
	 reachable via the Coder's Dependencies forward tab, not as a
	 top-level inspector tab."
	| modName appName |
	modName := [ self evaluateAndWait:
		'inspect(elem(', self resolve, '.query, 1))' ]
		on: Error do: [ nil ].
	modName isString ifFalse: [ ^ aView empty ].
	appName := [ (self evaluateAndWait:
		'Application.get_application(elem(', self resolve, '.query, 1))') symbol asString ]
		on: Error do: [ nil ].
	appName ifNil: [ ^ aView empty ].
	^ aView mondrian
		title: 'Dependencies';
		priority: 30;
		painting: [ :aMondrian |
			| callees callers allNodes edges short |
			short := [ :n | n withoutPrefix: 'Elixir.' ].
			callees := (self evaluateAndWait:
				'GtBridge.Analysis.callees(', modName, ', :', appName, ')
				|> Enum.map(&inspect/1) |> Enum.sort()') asList collect: [ :m | m asString ].
			callers := (self evaluateAndWait:
				'GtBridge.Analysis.callers(', modName, ', :', appName, ')
				|> Enum.map(&inspect/1) |> Enum.sort()') asList collect: [ :m | m asString ].
			allNodes := ({ modName } , callees , callers) asSet asArray sorted.
			aMondrian nodes
				shape: [ :n |
					| color |
					color := n = modName
						ifTrue: [ Color fromHexString: '#4285f4' ]
						ifFalse: [ (callees includes: n)
							ifTrue: [ Color fromHexString: '#e8f0fe' ]
							ifFalse: [ Color fromHexString: '#fce8e6' ] ].
					BrLabel new
						aptitude: BrGlamorousLabelAptitude new;
						text: (short value: n);
						padding: (BlInsets all: 6);
						background: color;
						geometry: (BlRoundedRectangleGeometry cornerRadius: 6);
						addEventHandlerOn: BlClickEvent do: [ :evt |
							evt consumed: true.
							evt currentTarget phlow spawnObject:
								(self evaluateAndWait:
									'GtBridge.Documentation.for_module(', n, ')') ] ];
				with: allNodes.
			edges := OrderedCollection new.
			callees do: [ :c | edges add: modName -> c ].
			callers do: [ :c | edges add: c -> modName ].
			aMondrian edges
				stencil: [ BeamMondrianHelpers edgeStencil ];
				fromCenterBottom;
				toCenterTop;
				connect: edges from: #key to: #value.
			aMondrian layout dominanceTree
				nodeDistance: 20;
				levelDistance: 40 ]
]

{ #category : 'gt-views' }
BeamDocumentationObject >> gtExecutableFunctionsFor: aView [
	"I show module functions. 0-arity functions execute on click."
	<gtView>
	<gtBeamView>
	^ aView columnedList
		title: 'Run';
		priority: 15;
		items: [ | funs |
			funs := [ self evaluateAndWait:
				'GtBridge.Analysis.exported_functions(elem(', self resolve, '.query, 1))' ]
				on: Error do: [ nil ].
			(funs isNil or: [ funs isKindOf: BeamBridgeEvalError ])
				ifTrue: [ #() ]
				ifFalse: [ [ funs asList ] on: Error do: [ #() ] ] ];
		column: 'Function' text: [ :each |
			[ (each attributeAt: #name), '/', (each attributeAt: #arity) asString ]
				on: Error do: [ '?' ] ];
		column: 'Action' text: [ :each |
			[ (each attributeAt: #arity) = 0
				ifTrue: [ 'Run' ] ifFalse: [ '' ] ]
				on: Error do: [ '' ] ] width: 60;
		send: [ :each |
			| mod fn arity |
			mod := self evaluateAndWait:
				'inspect(elem(', self resolve, '.query, 1))'.
			fn := each attributeAt: #name.
			arity := each attributeAt: #arity.
			arity = 0
				ifTrue: [ self evaluateAndWait: mod, '.', fn, '()' ]
				ifFalse: [ self evaluateAndWait:
					'GtBridge.Documentation.for_function(',
					mod, ', :', fn, ', ', arity asString, ')' ] ]
]

{ #category : 'gt-search' }
BeamDocumentationObject >> gtSearchFunctionsFor: aSearch [
	<gtSearch>
	^ aSearch list
		title: 'Functions';
		priority: 10;
		wantsToDisplayOnEmptyQuery: true;
		items: [
			| mod |
			mod := [ self evaluateAndWait:
				'inspect(elem(', self resolve, '.query, 1))' ]
				on: Error do: [ nil ].
			mod isString
				ifTrue: [ (self evaluateAndWait:
					'GtBridge.Analysis.exported_functions(', mod, ')') asList
						collect: [ :f | { mod. (f attributeAt: #name) asString. (f attributeAt: #arity) } ] ]
				ifFalse: [ #() ] ];
		itemName: [ :each | each second, '/', each third asString ];
		filterBySubstring;
		send: [ :each |
			self evaluateAndWait:
				'GtBridge.Documentation.for_function(', each first, ', :', each second, ', ', each third asString, ')' ]
]

{ #category : 'gt-views' }
BeamDocumentationObject >> gtInterfacesFor: aView [
	<gtView>
	<gtBeamView>
	"I draw this module's interfaces UmlClassDiagram-style; the body
	 is shared with BeamAtomObject via BeamMondrianHelpers."
	^ BeamMondrianHelpers
		interfacesDrawingFor: aView
		moduleExpr: 'elem(', self resolve, '.query, 1)'
		eval: [ :expr | self evaluateAndWait: expr ]
]

{ #category : 'gt-views' }
BeamDocumentationObject >> gtSourceFor: aView [
	"I override to hide the Source tab — the Coder tab already
	 has Source as an internal tab."
	^ aView empty
]

{ #category : 'gt-extensions' }
BeamDocumentationObject >> remoteViewsInContext: aContext [
	"I return empty — remote view declarations (Module Doc,
	 Functions, Types) are redundant as top-level tabs since the
	 Coder's Help tab already shows them. They're still accessible
	 via gtRemoteViewsFor: inside the Help tab."
	^ #()
]
