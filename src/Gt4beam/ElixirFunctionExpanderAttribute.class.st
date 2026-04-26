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
	"I return a module header + Elixir coder for the target function.
	 Ctrl-S inside the inline coder splices the edited text back into
	 the target module's source file via the same line-range splice
	 path the Functions tab uses."
	| coderModel vm |
	coderModel := GtElixirCoderModel new.
	coderModel elixirLinkApplicationStrategy: LeElixirApplicationStrategy new.
	coderModel contextModuleName: targetModule.
	coderModel sourceCode: (GtCoderExplicitStringSource new source: self fetchSource).
	vm := coderModel asCoderViewModel.
	vm
		when: GtSourceCoderViewModelSaveRequested
		do: [ :ann |
			self saveSource: coderModel currentSourceString.
			coderModel sourceCode: (GtCoderExplicitStringSource new source: self fetchSource).
			ann consumed: true ].
	^ BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ];
		margin: (BlInsets top: 3 left: 10 bottom: 3 right: 10);
		addChild: self buildHeader;
		addChild: vm asElement
]

{ #category : 'private' }
ElixirFunctionExpanderAttribute >> buildHeader [
	"I return the same breadcrumb header the filter rows use, so
	 |> inline expansions and Module > function/arity rows look
	 and click identically."
	^ ElixirFunctionCoderHeaderElement
		forModule: targetModule
		functionName: functionName
		arity: arity
		application: application
]

{ #category : 'private' }
ElixirFunctionExpanderAttribute >> saveSource: newSource [
	"I splice newSource into the target module's source file at this
	 expander's function/arity position.  Builds a transient module
	 coder so it can reuse spliceFunction:forFunction:arity: — the
	 splice is line-range based on start/end_line from all_functions,
	 so it works for both function and type rows."
	| path mc |
	path := application evaluateAndWait:
		'GtBridge.Resolve.source_file(', targetModule, ')'.
	(path isString and: [ path asFileReference exists ]) ifFalse: [ ^ self ].
	mc := ElixirModuleCoder new
		moduleName: targetModule;
		application: application;
		sourcePath: path.
	mc spliceFunction: newSource forFunction: functionName arity: arity
]

{ #category : 'private' }
ElixirFunctionExpanderAttribute >> fetchSource [
	"I fetch the target's source from the BEAM. Tries the function
	 first, then falls back to an @type with the same name/arity —
	 lets the inline expander work for both `Mod.fun(...)` calls and
	 `Mod.t()` type references in @spec / typedstruct field types."
	| reply |
	reply := application evaluateAndWait:
		'GtBridge.Analysis.function_or_type_source(',
		targetModule, ', "', functionName, '", ', arity asString, ')'.
	^ reply
		ifNil: [ '# not found: ', targetModule, '.', functionName, '/', arity asString ]
		ifNotNil: [ reply asString ]
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
