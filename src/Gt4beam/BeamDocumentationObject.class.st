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
			(ElixirModuleCoder new
				moduleName: modName;
				sourcePath: file;
				application: self application)
				asCoderViewModel asElement ]
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
				'mod = elem(', self resolve, '.query, 1)
				if function_exported?(mod, :__info__, 1) do
					mod.__info__(:functions)
				else
					mod.module_info(:exports)
				end
				|> Enum.sort()
				|> Enum.map(fn {name, arity} ->
					%{name: Atom.to_string(name), arity: arity}
				end)' ] on: Error do: [ #() ].
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
	^ aView composite
		title: 'Dependencies';
		priority: 30;
		views: {
			(aView columnedList
				title: 'Callees';
				priority: 1;
				items: [ (self evaluateAndWait:
					'GtBridge.Analysis.callees(', modName, ', :', appName, ')
					|> Enum.map(fn m -> inspect(m) end)
					|> Enum.sort()') asList collect: [ :m | m asString ] ];
				column: 'Module' text: [ :name | name copyReplaceAll: 'Elixir.' with: '' ];
				send: [ :name |
					self evaluateAndWait:
						'GtBridge.Documentation.for_module(', name, ')' ]).
			(aView columnedList
				title: 'Callers';
				priority: 2;
				items: [ (self evaluateAndWait:
					'GtBridge.Analysis.callers(', modName, ', :', appName, ')
					|> Enum.map(fn m -> inspect(m) end)
					|> Enum.sort()') asList collect: [ :m | m asString ] ];
				column: 'Module' text: [ :name | name copyReplaceAll: 'Elixir.' with: '' ];
				send: [ :name |
					self evaluateAndWait:
						'GtBridge.Documentation.for_module(', name, ')' ]) }
]

{ #category : 'gt-views' }
BeamDocumentationObject >> gtSourceFor: aView [
	<gtView>
	| file |
	file := self sourceFile.
	file isString ifFalse: [ ^ aView empty ].
	file := file asFileReference.
	file exists ifFalse: [ ^ aView empty ].
	^ aView explicit
		title: 'Source';
		priority: 110;
		stencil: [
			| pane lineRange |
			lineRange := [ self functionLines ] on: Error do: [ nil ].
			pane := file gtEditorView.
			pane childNamed: #editor ifFound: [ :ed |
				ed aptitude: BrGlamorousCodeEditorAptitude.
				ed editor styler: ElixirParser gtStyler.
				lineRange ifNotNil: [
					| aText startChar endChar lines |
					aText := ed text.
					lines := aText asString lines.
					startChar := 0.
					1 to: lineRange first - 1 do: [ :i |
						startChar := startChar + (lines at: i) size + 1 ].
					endChar := startChar.
					lineRange first to: (lineRange second min: lines size) do: [ :i |
						endChar := endChar + (lines at: i) size + 1 ].
					(aText from: startChar + 1 to: endChar)
						attributes: { BlTextDecorationAttribute new underline
							beNotOverwritableByStyler;
							color: BrGlamorousColors textHighlightColor } ].
				lineRange ifNotNil: [ ed scrollToPosition: lineRange first ] ].
			pane ];
		actionButtonIcon: BrGlamorousVectorIcons accept
			tooltip: 'Save & compile'
			action: [ :aButton :aBrTab :aButtonModel |
				aButton phlow firstParentWithView
					allChildrenBreadthFirstDetect: [ :el | el isKindOf: BrEditor ]
					ifFound: [ :ed |
						| b64 result path |
						path := file fullName.
						b64 := ZnBase64Encoder new encode: ed text asString utf8Encoded.
						result := self evaluateAndWait:
							'content = Base.decode64!("', b64, '")
							File.write!("', path, '", content)
							Code.compile_file("', path, '")
							|> length()
							|> then(fn n -> "Saved and compiled #{n} modules from ', (path copyAfterLast: $/), '" end)'.
						aButton phlow spawnObject: result ]
					ifNone: [ ] ]
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
