Class {
	#name : 'ElixirFunctionExpanderAttribute',
	#superclass : 'BrGlamorousTriangleExpanderTextAttribute',
	#instVars : [
		'targetModule',
		'functionName',
		'arity',
		'application',
		'currentCoderModel'
	],
	#category : 'Gt4beam',
	#package : 'Gt4beam'
}

{ #category : 'building' }
ElixirFunctionExpanderAttribute >> buildExpandedElement [
	"I return a module header + Elixir coder for the target function.
	 Ctrl-S inside the inline coder splices the edited text back into
	 the target module's source file via the same line-range splice
	 path the Functions tab uses.

	 The coderModel is stashed in currentCoderModel so the
	 BeamModuleRecompiled subscription set up in initialize can refresh
	 the inline source when the target module recompiles externally
	 (edited from another coder in the same image, an Emacs save once
	 the file watcher lands, etc.)."
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
	currentCoderModel := coderModel.
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
	"Subscription is deferred to the targetModule:functionName:arity:application:
	 setter — at construction time targetModule isn't known yet, and
	 per-module dispatch needs the name to pick the right announcer."
	super initialize.
	self attributesCreatingBlock: [
		BrTextAdornmentDynamicAttribute new
			beAppend;
			stencil: [ self buildExpandedElement ] ]
]

{ #category : 'announcements' }
ElixirFunctionExpanderAttribute >> onTargetModuleRecompiled: anAnnouncement [
	"I refresh my inline coder's source on any recompile event —
	 narrow dispatch means events for other modules don't reach me.
	 No-op if I haven't been expanded yet (no model held).

	 Prefer the fresh function entry inside the announcement payload
	 over a follow-up `function_or_type_source` bridge call; fall back
	 to the bridge when the payload doesn't carry it (sibling module
	 events, or my target is a @type with the same name/arity)."
	| source |
	currentCoderModel ifNil: [ ^ self ].
	source := (self sourceFromAnnouncement: anAnnouncement)
		ifNil: [ self fetchSource ].
	currentCoderModel sourceCode: (GtCoderExplicitStringSource new source: source)
]

{ #category : 'printing' }
ElixirFunctionExpanderAttribute >> printOn: aStream [
	aStream
		nextPutAll: 'elixir-expander: ';
		nextPutAll: targetModule asString;
		nextPut: $.;
		nextPutAll: functionName asString
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
ElixirFunctionExpanderAttribute >> sourceFromAnnouncement: anAnnouncement [
	"I extract my target function's source from the payload's function
	 list. Returns nil when the payload is bare (sibling) or when my
	 target is a @type that won't appear in the function list — the
	 caller falls back to fetchSource in either case."
	| entries match |
	entries := anAnnouncement functions ifNil: [ ^ nil ].
	(entries isKindOf: BeamProxyObject) ifTrue: [ entries := entries asList ].
	match := entries detect: [ :e |
		(e attributeAt: #name) asString = functionName asString
			and: [ (e attributeAt: #arity) = arity ] ]
		ifNone: [ nil ].
	^ match ifNotNil: [ (match attributeAt: #source) asString ]
]

{ #category : 'accessing' }
ElixirFunctionExpanderAttribute >> targetModule: mod functionName: fn arity: ar application: app [
	"I subscribe (weakly) to the per-module announcer for `mod` — narrow
	 events only. If reassigned to a different target, drop the prior
	 subscription first so I don't leak."
	targetModule ifNotNil: [
		(BeamEventAnnouncer for: targetModule) unsubscribe: self ].
	targetModule := mod.
	functionName := fn.
	arity := ar.
	application := app.
	(BeamEventAnnouncer for: targetModule) weak
		when: BeamModuleRecompiled
		send: #onTargetModuleRecompiled:
		to: self
]
