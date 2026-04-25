Class {
	#name : 'ElixirFunctionExpanderAttribute',
	#superclass : 'BrGlamorousTriangleExpanderTextAttribute',
	#instVars : [
		'targetModule',
		'functionName',
		'arity',
		'application'
	],
	#category : 'Gt4beam',
	#package : 'Gt4beam'
}

{ #category : 'building' }
ElixirFunctionExpanderAttribute >> buildExpandedElement [
	"I return a module header + Elixir coder for the target function."
	| coderModel vm |
	coderModel := GtElixirCoderModel new.
	coderModel elixirLinkApplicationStrategy: LeElixirApplicationStrategy new.
	coderModel contextModuleName: targetModule.
	coderModel sourceCode: (GtCoderExplicitStringSource new source: self fetchSource).
	vm := coderModel asCoderViewModel.
	^ BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ];
		margin: (BlInsets top: 3 left: 10 bottom: 3 right: 10);
		addChild: self buildHeader;
		addChild: vm asElement
]

{ #category : 'building' }
ElixirFunctionExpanderAttribute class >> buildHeaderForModule: aModuleName functionName: aFunctionName arity: anArity application: anApplication [
	"I return a compact horizontal pane with three labels:
	 module > function/arity. Each module/function label fires its
	 action via addEventFilterOn: (capture phase) so first-click
	 works even when list rows want to consume clicks."
	| moduleLabel separatorLabel functionLabel |
	moduleLabel := BrLabel new
		aptitude: (BrGlamorousLabelAptitude new
			foreground: (Color fromHexString: '666666'); fontSize: 11);
		text: aModuleName.
	moduleLabel addEventFilterOn: BlClickEvent do: [ :evt |
		evt consumed: true.
		anApplication ifNotNil: [
			evt currentTarget phlow spawnObject:
				(anApplication evaluateAndWait:
					'GtBridge.Documentation.for_module(', aModuleName, ')') ] ].

	separatorLabel := BrLabel new
		aptitude: (BrGlamorousLabelAptitude new
			foreground: (Color fromHexString: 'aaaaaa'); fontSize: 11);
		text: ' > '.

	functionLabel := BrLabel new
		aptitude: (BrGlamorousLabelAptitude new bold; fontSize: 11);
		text: aFunctionName, '/', anArity asString.
	functionLabel addEventFilterOn: BlClickEvent do: [ :evt |
		evt consumed: true.
		anApplication ifNotNil: [
			evt currentTarget phlow spawnObject:
				(anApplication evaluateAndWait:
					'GtBridge.Documentation.for_function(', aModuleName,
						', :', aFunctionName, ', ', anArity asString, ')') ] ].

	^ BrHorizontalPane new
		hFitContent;
		vFitContent;
		padding: (BlInsets top: 1 left: 4 bottom: 1 right: 4);
		addChild: moduleLabel;
		addChild: separatorLabel;
		addChild: functionLabel;
		yourself
]

{ #category : 'private' }
ElixirFunctionExpanderAttribute >> buildHeader [
	^ self class
		buildHeaderForModule: targetModule
		functionName: functionName
		arity: arity
		application: application
]

{ #category : 'private' }
ElixirFunctionExpanderAttribute >> fetchSource [
	"I fetch the target function's source from the BEAM."
	^ [ | fns match |
		fns := (application evaluateAndWait:
			'GtBridge.Analysis.all_functions(', targetModule, ')') asList.
		match := fns
			detect: [ :f | (f attributeAt: #name) asString = functionName
				and: [ (f attributeAt: #arity) asInteger = arity ] ]
			ifNone: [ nil ].
		match
			ifNotNil: [ (match attributeAt: #source) asString ]
			ifNil: [ '# not found: ', targetModule, '.', functionName, '/', arity asString ] ]
		on: Error do: [ '# error fetching source' ]
]

{ #category : 'initialization' }
ElixirFunctionExpanderAttribute >> initialize [
	super initialize.
	self attributesCreatingBlock: [
		BrTextAdornmentDynamicAttribute new
			beAppend;
			stencil: [ self buildExpandedElement ] ]
]

{ #category : 'printing' }
ElixirFunctionExpanderAttribute >> printOn: aStream [
	aStream
		nextPutAll: 'elixir-expander: ';
		nextPutAll: targetModule asString;
		nextPut: $.;
		nextPutAll: functionName asString
]

{ #category : 'accessing' }
ElixirFunctionExpanderAttribute >> targetModule: mod functionName: fn arity: ar application: app [
	targetModule := mod.
	functionName := fn.
	arity := ar.
	application := app
]
