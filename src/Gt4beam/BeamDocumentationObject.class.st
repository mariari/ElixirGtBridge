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
	| file modName |
	file := self sourceFile.
	file isString ifFalse: [ ^ aView empty ].
	file asFileReference exists ifFalse: [ ^ aView empty ].
	modName := self evaluateAndWait:
		'inspect(elem(', self resolve, '.query, 1))'.
	modName isString ifFalse: [ ^ aView empty ].
	^ aView explicit
		title: 'Coder';
		priority: 5;
		stencil: [
			| coder lineRange |
			coder := ElixirModuleCoder new
				moduleName: modName;
				sourcePath: file;
				application: self application.
			lineRange := [ self functionLines ] on: Error do: [ nil ].
			lineRange ifNotNil: [ coder focusLine: lineRange ].
			coder asCoderViewModel asElement ]
]

{ #category : 'gt-views' }
BeamDocumentationObject >> gtDependenciesFor: aView [
	<gtView>
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
			short := [ :n | n copyReplaceAll: 'Elixir.' with: '' ].
			callees := (self evaluateAndWait:
				'GtBridge.Analysis.callees(', modName, ', :', appName, ')
				|> Enum.map(&inspect/1) |> Enum.sort()') asList collect: [ :m | m asString ].
			callers := (self evaluateAndWait:
				'GtBridge.Analysis.callers(', modName, ', :', appName, ')
				|> Enum.map(&inspect/1) |> Enum.sort()') asList collect: [ :m | m asString ].
			allNodes := ({ modName } , callers , callees) asSet asOrderedCollection.
			edges := OrderedCollection new.
			callers do: [ :c | edges add: c -> modName ].
			callees do: [ :c | edges add: modName -> c ].
			aMondrian nodes
				stencil: [ :name |
					BeamMondrianHelpers
						nodeLabeled: (short value: name)
						color: (name = modName
							ifTrue: [ Color fromHexString: '#fff3cd' ]
							ifFalse: [ (callers includes: name)
								ifTrue: [ Color fromHexString: '#d4e6f1' ]
								ifFalse: [ Color fromHexString: '#d5f5e3' ] ])
						onClick: [ :evt |
							evt currentTarget phlow spawnObject:
								(self evaluateAndWait:
									'GtBridge.Documentation.for_module(', name, ')') ] ];
				with: allNodes.
			aMondrian edges stencil: [ BeamMondrianHelpers edgeStencil ];
				connect: edges from: #key to: #value.
			aMondrian layout horizontalDominanceTree ]
]

{ #category : 'gt-views' }
BeamDocumentationObject >> gtExecutableFunctionsFor: aView [
	"I show module functions. 0-arity functions execute on click."
	<gtView>
	^ aView columnedList
		title: 'Run';
		priority: 15;
		items: [ | funs |
			funs := [ self evaluateAndWait:
				'GtBridge.Analysis.exported_functions(elem(', self resolve, '.query, 1))' ]
				on: Error do: [ #() ].
			funs asList ];
		column: 'Function' text: [ :each |
			(each attributeAt: #name), '/', (each attributeAt: #arity) asString ];
		column: 'Action' text: [ :each |
			(each attributeAt: #arity) = 0
				ifTrue: [ '▶ Run' ] ifFalse: [ '' ] ] width: 60;
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
