Class {
	#name : 'ElixirFunctionExpanderAttribute',
	#superclass : 'BrGlamorousTriangleExpanderTextAttribute',
	#instVars : [
		'targetModule',
		'functionName',
		'arity',
		'application',
		'currentCoderModel',
		'sourceCache'
	],
	#category : 'Gt4beam-Styling',
	#package : 'Gt4beam'
}

{ #category : 'private' }
ElixirFunctionExpanderAttribute >> bridgeFetchSource [
	"I bridge-fetch the target's source.  Used as the cold-start
	 path and as the fallback when the cache doesn't carry the
	 entry (e.g. type references)."
	| reply |
	reply := application evaluateAndWait:
		'GtBridge.Analysis.function_or_type_source(',
		targetModule, ', "', functionName, '", ', arity asString, ')'.
	^ reply
		ifNil: [ '# not found: ', targetModule, '.', functionName, '/', arity asString ]
		ifNotNil: [ reply asString ]
]

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
	 and click identically.  The 'Create module' wrench moved out
	 of here onto `ElixirUnknownModuleAttribute`, attached inline
	 by the styler at the unknown identifier itself — that's the
	 placement that actually reaches unresolved references (the
	 |> expander only renders for resolvable calls)."
	^ ElixirFunctionCoderHeaderElement
		forModule: targetModule
		functionName: functionName
		arity: arity
		application: application
]

{ #category : 'private' }
ElixirFunctionExpanderAttribute >> fetchSource [
	"I fetch the target's source.  Try the per-module cache first;
	 on miss fall back to the bridge.  The cache populates from
	 `BeamModuleRecompiled` events, so first reads always miss
	 until something has recompiled the module — that's expected,
	 and the bridge fallback covers the cold-start path including
	 type references (`@type t :: Foo.t()`) which never appear in
	 a recompile's `functions` payload."
	| cached |
	cached := sourceCache
		ifNotNil: [ sourceCache sourceForFunction: functionName arity: arity ].
	cached ifNotNil: [ ^ cached ].
	^ self bridgeFetchSource
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

{ #category : 'subscriptions' }
ElixirFunctionExpanderAttribute >> onSourceChanged: anAnnouncement [
	"I refresh my inline coder when the cache fires a narrow source-
	 changed event for my exact function/arity.  Cache has already
	 done the work of extracting + storing the new source — I just
	 read from the announcement and re-render.  No bridge call.

	 Events for other functions/arities in the same module reach me
	 (per-module announcer fan-out), so I filter here.  This is the
	 'consumers just read' half of the FRP shape — heavy work
	 happened once in the cache, cheap re-render happens N times
	 across consumers."
	currentCoderModel ifNil: [ ^ self ].
	(anAnnouncement function = functionName asString
		and: [ anAnnouncement arity = arity ]) ifFalse: [ ^ self ].
	currentCoderModel sourceCode:
		(GtCoderExplicitStringSource new source: anAnnouncement source)
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

{ #category : 'subscriptions' }
ElixirFunctionExpanderAttribute >> subscribeToSourceChanges [
	"I subscribe (weakly) to my module's narrow `BeamModuleSourceChanged`
	 event — fired by `BeamModuleSourceCache` after it processes the
	 underlying recompile.  Cache is the sole subscriber to recompile
	 for this module; I just listen for the narrow event and read."
	(BeamEventAnnouncer for: targetModule) weak
		when: BeamModuleSourceChanged
		send: #onSourceChanged:
		to: self
]

{ #category : 'accessing' }
ElixirFunctionExpanderAttribute >> targetModule: mod functionName: fn arity: ar application: app [
	"I set my target's identity and re-wire event subscription via
	 the helpers in the `subscriptions` protocol.  Cache is held
	 strongly so it stays alive as long as I do — the cache's
	 class-side registry is a `WeakValueDictionary`, so my
	 reference is what keeps it from being GC'd."
	self unsubscribeFromSourceChanges.
	targetModule := mod.
	functionName := fn.
	arity := ar.
	application := app.
	sourceCache := BeamModuleSourceCache for: targetModule.
	self subscribeToSourceChanges
]

{ #category : 'subscriptions' }
ElixirFunctionExpanderAttribute >> unsubscribeFromSourceChanges [
	"I drop my prior subscription before retargeting — otherwise I'd
	 leak listeners on the old module's announcer."
	targetModule ifNotNil: [
		(BeamEventAnnouncer for: targetModule) unsubscribe: self ]
]
