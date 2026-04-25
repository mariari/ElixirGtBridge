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

{ #category : 'private' }
ElixirFunctionExpanderAttribute >> buildHeader [
	"I return a header bar with two click targets: clicking the
	 module name spawns module docs; clicking the function/arity
	 label spawns the specific function's docs."
	| header moduleLabel separatorLabel functionLabel |
	moduleLabel := BrLabel new
		aptitude: (BrGlamorousLabelAptitude new
			foreground: (Color fromHexString: '666666'); fontSize: 11);
		text: targetModule.
	moduleLabel addEventHandlerOn: BlClickEvent do: [ :evt |
		evt consumed: true.
		evt currentTarget phlow spawnObject:
			(application evaluateAndWait:
				'GtBridge.Documentation.for_module(', targetModule, ')') ].

	separatorLabel := BrLabel new
		aptitude: (BrGlamorousLabelAptitude new
			foreground: (Color fromHexString: '999999'); fontSize: 11);
		text: ' > '.

	functionLabel := BrLabel new
		aptitude: (BrGlamorousLabelAptitude new bold; fontSize: 11);
		text: functionName, '/', arity asString.
	functionLabel addEventHandlerOn: BlClickEvent do: [ :evt |
		evt consumed: true.
		evt currentTarget phlow spawnObject:
			(application evaluateAndWait:
				'GtBridge.Documentation.for_function(', targetModule,
					', :', functionName, ', ', arity asString, ')') ].

	header := BrHorizontalPane new
		hMatchParent; vFitContent;
		padding: (BlInsets top: 4 left: 6 bottom: 2 right: 6);
		background: (Color fromHexString: 'f0f0f0');
		border: (BlBorder paint: (Color fromHexString: 'e0e0e0') width: 1);
		addChild: moduleLabel;
		addChild: separatorLabel;
		addChild: functionLabel;
		yourself.
	^ header
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
