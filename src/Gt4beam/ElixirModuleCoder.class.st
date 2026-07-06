Class {
	#name : 'ElixirModuleCoder',
	#superclass : 'GtCoderModel',
	#traits : 'TGtCoderTrait',
	#classTraits : 'TGtCoderTrait classTrait',
	#instVars : [
		'sourcePath',
		'moduleName',
		'application',
		'focusLine',
		'focusFunctionTarget',
		'sessionId',
		'selfObject',
		'saving',
		'sourceCache'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'instance creation' }
ElixirModuleCoder class >> forModule: aModuleName application: anApp [
	"I fetch the module's source file path via the BEAM bridge.
	 The case expression guarantees the result is either a binary
	 or nil — without it, compile_source's to_string return value
	 has sometimes come back across the bridge as a BeamProxyObject
	 wrapping the raw Erlang charlist, which then DNU'd when the
	 Smalltalk side tried to use it as a String path."
	| path |
	path := [ anApp evaluateAndWait:
		'case GtBridge.Resolve.source_file(', aModuleName, ') do
		 nil -> nil
		 s when is_binary(s) -> s
		 s when is_list(s) -> List.to_string(s)
		 _ -> nil
		 end' ]
		on: Error do: [ nil ].
	^ self new
		moduleName: aModuleName;
		application: anApp;
		sourcePath: ((path isKindOf: String) ifTrue: [ path ] ifFalse: [ nil ]);
		yourself
]

{ #category : 'actions' }
ElixirModuleCoder >> addFunction: newText [
	"I insert newText just before the module's closing `end`, so new
	 functions land after any types, attributes, and existing defs.
	 findLast: is critical — a backward loop without early termination
	 would fall through every `end` and land on the earliest one (a
	 nested def's close), splicing the new function inside that def."
	| lines lastEnd newLines |
	lines := self sourceCode lines asOrderedCollection.
	lastEnd := lines findLast: [ :line | line trimBoth = 'end' ].
	lastEnd = 0 ifTrue: [ lastEnd := lines size + 1 ].
	newLines := (lines copyFrom: 1 to: lastEnd - 1) asOrderedCollection.
	newLines add: ''.
	newLines addAll: newText lines.
	newLines addAll: (lines copyFrom: lastEnd to: lines size).
	^ self saveAndCompile: (String lf join: newLines)
]

{ #category : 'accessing' }
ElixirModuleCoder >> application [
	^ application
]

{ #category : 'accessing' }
ElixirModuleCoder >> application: anApp [
	application := anApp
]

{ #category : 'accessing' }
ElixirModuleCoder >> asCoderViewModel [
	^ ElixirModuleCoderViewModel new coder: self
]

{ #category : 'private' }
ElixirModuleCoder >> buildAddFunctionDraftPaneIn: container afterRow: addRow [
	"I insert a draft editor pane immediately after addRow, seeded with a
	 new-function template.  It's an ElixirFunctionCoder (no eval buttons,
	 dedent), so its own Save appends via addFunction:; completion sees my
	 imports/aliases through my editor session.  The pane removes itself
	 once the append recompiles (the same GtCoderSourceCodeChanged the
	 streaming list refreshes on).  Cancel just removes the pane."
	| coder vm editor draftPane header existing |
	existing := container children detect: [ :c | c == addRow ] ifNone: [ nil ].
	existing ifNil: [ ^ self ].
	"Bail if a draft is already open — addRow is always at index 1 and
	 if there's a draft it sits at index 2; we don't want two drafts."
	container children size > 2 ifTrue: [ ^ self ].
	coder := ElixirFunctionCoder forNewFunctionIn: self.
	vm := coder asCoderViewModel.
	vm expanded: true.
	editor := vm asElement matchParent.
	header := BrHorizontalPane new
		hMatchParent;
		vFitContent;
		alignCenterLeft;
		padding: (BlInsets top: 3 left: 6 bottom: 3 right: 6);
		addChild: (BrLabel new
			aptitude: (BrGlamorousLabelAptitude new glamorousCodeFont; fontSize: 12);
			text: 'New function');
		addChild: (BrFrame new hMatchParent vFitContent);
		addChild: (BrButton new
			aptitude: BrGlamorousButtonWithIconAptitude;
			icon: BrGlamorousVectorIcons cancel;
			beSmallSize;
			label: 'Cancel';
			action: [ :btn |
				draftPane removeFromParent.
				self announcer unsubscribe: draftPane ]);
		yourself.
	draftPane := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical exact: 220 ];
		padding: (BlInsets all: 4);
		border: (BlBorder paint: (Color gray alpha: 0.4) width: 1);
		addChild: header;
		addChild: editor;
		yourself.
	self announcer
		when: GtCoderSourceCodeChanged
		do: [ :ann |
			draftPane removeFromParent.
			self announcer unsubscribe: draftPane ]
		for: draftPane.
	container addChild: draftPane at: 2
]

{ #category : 'private' }
ElixirModuleCoder >> buildExampleMapElement [
	"I build a Mondrian graph of example dependencies."
	| mondrian data edges nodes app modName |
	app := self application.
	modName := self moduleName.
	data := (app evaluateAndWait:
		'GtBridge.Analysis.example_deps(', modName, ')') asList.
	edges := OrderedCollection new.
	data do: [ :pair |
		| from tos |
		from := pair itemAt: 0.
		tos := (pair itemAt: 1) asList.
		tos do: [ :to | edges add: from -> to ] ].
	nodes := data collect: [ :pair | pair itemAt: 0 ].
	mondrian := GtMondrian new.
	mondrian nodes
		stencil: [ :name |
			BeamMondrianHelpers
				nodeLabeled: name
				color: (Color fromHexString: '#e6f5ec')
				onClick: [ :evt |
					evt target phlow spawnObject:
						(app newCommandFactory << (modName, '.', name, '()'); sendAndWait) ] ];
		with: nodes.
	mondrian edges stencil: [ BeamMondrianHelpers edgeStencil ];
		connectToAll: [ :name |
			(edges select: [ :e | e key = name ]) collect: #value ].
	mondrian layout horizontalDominanceTree.
	^ mondrian root
]

{ #category : 'private' }
ElixirModuleCoder >> buildFunctionsViewElement [
	"I build the Functions tab. If focusLine is set, I set a scroll
	 target on the view model — the streaming element handles
	 scroll via list scrollToItemSuchThat:offset: when the matching
	 item loads (same pattern as GtPharoStreamingMethodsCoderElement).
	 Each function coder starts folded so the user scans the list."
	| container addRow streaming vm streamingElement focusStart |
	container := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical matchParent ].
	addRow := BrHorizontalPane new
		hMatchParent;
		vFitContent;
		padding: (BlInsets top: 3 left: 6 bottom: 3 right: 6);
		addChild: (BrButton new
			aptitude: BrGlamorousButtonWithIconAptitude;
			icon: BrGlamorousVectorIcons add;
			beSmallSize;
			label: 'Add function';
			action: [ :btn | self buildAddFunctionDraftPaneIn: container afterRow: addRow ]);
		yourself.
	streaming := ElixirFunctionStreamingModel forModuleCoder: self.
	vm := ElixirFoldedCodersViewModel new
		streamingCodersModel: streaming;
		yourself.
	streamingElement := ElixirFunctionStreamingElement new
		streamingCodersViewModel: vm;
		yourself.
	"Caller-supplied focusFunctionTarget wins (works for macro-generated
	 entries with no source line, and for source-having entries when
	 the caller knows the function name).  Otherwise build a startLine
	 target from focusLine."
	focusFunctionTarget
		ifNotNil: [ vm scrollToTarget: focusFunctionTarget ]
		ifNil: [
			focusStart := focusLine ifNotNil: [ :lines |
				lines isArray ifTrue: [ lines first ] ifFalse: [ lines ] ].
			focusStart ifNotNil: [
				vm scrollToTarget: (ElixirFunctionScrollTarget new startLine: focusStart) ] ].
	container
		addChild: addRow;
		addChild: streamingElement matchParent.
	^ container
]

{ #category : 'private' }
ElixirModuleCoder >> buildSourceViewElement [
	"I build a self-refreshing container for the Source tab. The inner
	 coder is rebuilt whenever GtCoderSourceCodeChanged fires on me —
	 my #initialize subscribes weakly to the global bus and republishes
	 matching events as local GtCoderSourceCodeChanged, so the closure
	 captured here lives only as long as I do.
	 If focusLine is set, I scroll to that line after rendering."

	| container rebuild |
	container := BlElement new
			layout: BlLinearLayout vertical;
			constraintsDo: [ :c | 
				c horizontal matchParent.
				c vertical matchParent ].
	rebuild := [ | coderModel vm element |
		container removeChildren.
		coderModel := GtElixirCoderModel new.
		coderModel elixirLinkApplicationStrategy: LeElixirApplicationStrategy new.
		coderModel contextModuleName: moduleName.
		coderModel
			sourceCode: (GtCoderExplicitStringSource new source: self sourceCode).
		vm := coderModel asCoderViewModel.
		vm expanded: true.
		vm
			when: GtSourceCoderViewModelSaveRequested
			do: [ :ann | 
				self saveAndCompile: coderModel currentSourceString.
				ann consumed: true ].
		focusLine ifNotNil: [ :lines |
			| startLine source lineCount pos |
			startLine := lines isArray
				ifTrue: [ lines isEmpty ifTrue: [ nil ] ifFalse: [ lines first ] ]
				ifFalse: [ lines ].
			source := self sourceCode.
			lineCount := source lines size.
			(startLine isInteger and: [ startLine > 0 and: [ startLine <= lineCount ] ])
				ifTrue: [
					pos := 0.
					1 to: startLine - 1 do: [ :i |
						pos := pos + (source lines at: i) size + 1 ].
					vm moveCursorTo: pos.
					vm scrollToLine: startLine withCharacterPosition: 1 ] ].
		container addChild: vm asElement matchParent ].
	rebuild value.
	self announcer
		when: GtCoderSourceCodeChanged
		do: [ :ann | rebuild value ]
		for: self.
	^ container
]

{ #category : 'accessing' }
ElixirModuleCoder >> coderName [
	^ moduleName
]

{ #category : 'accessing' }
ElixirModuleCoder >> contextModuleName [
	"Common interface with GtElixirCoderModel and ElixirFunctionCoder
	 — lets context-aware tooling (styler, completion) call one
	 method regardless of which Elixir coder it's attached to."
	^ moduleName
]

{ #category : 'accessing' }
ElixirModuleCoder >> editorSessionId [
	"I return a unique session ID for this coder instance, with the
	 module's imports/aliases/requires loaded. The session is finalized
	 when this coder is GC'd."
	^ sessionId ifNil: [
		sessionId := 'editor_', moduleName, '_', UUID new asString.
		application evaluateAndWait:
			'GtBridge.Eval.Preamble.editor_session(', moduleName, ', "', sessionId, '")'.
		FinalizationRegistry default
			add: self
			finalizer: (BeamSessionFinalizer sessionId: sessionId application: application).
		sessionId ]
]

{ #category : 'accessing' }
ElixirModuleCoder >> focusFunctionTarget: aTarget [
	"I take an ElixirFunctionScrollTarget directly so callers that
	 know the function name+arity (BeamDocumentationObject>>gtCoderFor:)
	 can land on macro-generated entries that share startLine = 0."
	focusFunctionTarget := aTarget
]

{ #category : 'accessing' }
ElixirModuleCoder >> focusLine [
	^ focusLine
]

{ #category : 'accessing' }
ElixirModuleCoder >> focusLine: aLineNumber [
	focusLine := aLineNumber
]

{ #category : 'accessing' }
ElixirModuleCoder >> functionEntries [
	"I return all function entries with line ranges, annotations,
	 and source text.

	 The per-module `BeamModuleSourceCache` is the canonical store —
	 a recompile event primes its `entries` list directly from the
	 announcement payload, so warm reads return the cache list with
	 no bridge round-trip.

	 On cold start (cache empty) I bridge-call
	 `Analysis.all_functions/1` and materialize any BeamProxyObject
	 so callers get a uniform iterable type.  Cold-start results are
	 NOT pushed into the cache — that's the cache's job, driven by
	 events; my fallback just keeps the UI alive until the first
	 recompile primes it."
	| cached result |
	cached := sourceCache entries.
	cached isNotEmpty ifTrue: [ ^ cached ].
	result := [ application evaluateAndWait:
		'GtBridge.Analysis.all_functions(', moduleName, ')' ]
		on: Error do: [ #() ].
	^ (result isKindOf: BeamProxyObject)
		ifTrue: [ result asList ]
		ifFalse: [ result ]
]

{ #category : 'as yet unclassified' }
ElixirModuleCoder >> gtDependenciesViewFor: aView context: aContext [
	<gtElixirModuleView>
	^ aView forward
		title: 'Dependencies';
		priority: 40;
		object: [ self application evaluateAndWait:
			'GtBridge.Documentation.for_module(', self moduleName, ')' ];
		view: #gtDependenciesFor:
]

{ #category : 'gt-extensions' }
ElixirModuleCoder >> gtExamplesViewFor: aView context: aContext [
	<gtElixirModuleView>
	| hasExamples |
	hasExamples := [ self application evaluateAndWait:
		'function_exported?(', self moduleName, ', :__examples__, 0)' ]
		on: Error do: [ false ].
	hasExamples ifFalse: [ ^ aView empty ].
	^ aView explicit
		title: 'Examples';
		priority: 30;
		stencil: [ self buildExampleMapElement ]
]

{ #category : 'gt-extensions' }
ElixirModuleCoder >> gtFunctionsViewFor: aView context: aContext [
	<gtElixirModuleView>
	self hasFunctions ifFalse: [ ^ aView empty ].
	^ aView explicit
		title: 'Functions';
		priority: 9;
		stencil: [ self buildFunctionsViewElement ]
]

{ #category : 'as yet unclassified' }
ElixirModuleCoder >> gtHelpViewFor: aView context: aContext [
	<gtElixirModuleView>
	^ aView forward
		title: 'Help';
		priority: 25;
		object: [ self application evaluateAndWait:
			'GtBridge.Documentation.for_module(', self moduleName, ')' ];
		view: #gtRemoteViewsFor:
]

{ #category : 'gt-extensions' }
ElixirModuleCoder >> gtSourceViewFor: aView context: aContext [
	<gtElixirModuleView>
	self hasLocalSource ifFalse: [ ^ aView empty ].
	^ aView explicit
		title: 'Source';
		priority: 20;
		stencil: [ self buildSourceViewElement ]
]

{ #category : 'as yet unclassified' }
ElixirModuleCoder >> hasFunctions [
	"I return true if the bridge can enumerate my functions.
	 Precompiled modules without debug info return empty."
	^ [ self functionEntries isNotEmpty ]
		on: Error do: [ false ]
]

{ #category : 'as yet unclassified' }
ElixirModuleCoder >> hasLocalSource [
	"I return true if my sourcePath is a String pointing to an
	 existing file on this machine. Guarding on isKindOf: String
	 so a stray BeamProxyObject (from a bridge quirk we've seen on
	 some modules) degrades to 'no local source' instead of
	 crashing on #asFileReference."
	(sourcePath isKindOf: String) ifFalse: [ ^ false ].
	^ sourcePath asFileReference exists
]

{ #category : 'initialization' }
ElixirModuleCoder >> initialize [
	"Subscription to BeamEventAnnouncer is deferred to my `moduleName:`
	 setter — at construction time my module name isn't known yet, and
	 per-module dispatch needs the name to pick the right announcer.
	 Source tab subscribers still keep their cheap closure-based pattern
	 against `self announcer`; my onBeamModuleRecompiled: handler
	 republishes the global event as a local GtCoderSourceCodeChanged."
	super initialize
]

{ #category : 'accessing' }
ElixirModuleCoder >> moduleName [
	^ moduleName
]

{ #category : 'accessing' }
ElixirModuleCoder >> moduleName: aString [
	"Canonicalize on input: strip the 'Elixir.' atom prefix that the
	 inspector path passes through (e.g. 'Elixir.LocalUpload.Uploads.Upload').
	 BeamModuleRecompiled events carry the bare form, so storing the
	 bare form here lets the per-module announcer key just match.

	 I also subscribe (weakly) to my module's per-module announcer here
	 — `initialize` can't because moduleName isn't known yet. If
	 reassigned to a different module, drop the prior subscription
	 first so I don't leak."
	| bare |
	bare := (aString beginsWith: 'Elixir.')
		ifTrue: [ aString copyFrom: 8 to: aString size ]
		ifFalse: [ aString ].
	self unsubscribeFromEntries.
	moduleName := bare.
	"Hold the per-module cache strongly via an ivar.  The class-side
	 registry is a WeakValueDictionary, so without a strong holder
	 the cache gets GC'd between the moduleName: setter return and
	 the next recompile event, which would silently drop the
	 BeamModuleEntriesUpdated chain on the floor."
	sourceCache := BeamModuleSourceCache for: moduleName.
	self subscribeToEntries
]

{ #category : 'subscriptions' }
ElixirModuleCoder >> onBeamModuleEntriesUpdated: anAnnouncement [
	"I translate the per-module cache's coarse `BeamModuleEntriesUpdated`
	 (fired once per recompile after the cache primes its entries
	 list) into my local `GtCoderSourceCodeChanged` for my own
	 announcer-based subscribers (Source tab rebuild, the function
	 streaming list).

	 The entries themselves live in `BeamModuleSourceCache`; I'm
	 just a translator from cache-event to local-coder-event.  I no
	 longer hold my own `cachedFunctionEntries` ivar — `functionEntries`
	 reads straight from the cache."
	self announce: (GtCoderSourceCodeChanged new coder: self)
]

{ #category : 'accessing' }
ElixirModuleCoder >> pageAliasSource [
	"Common interface with GtElixirCoderModel and ElixirFunctionCoder.
	 Module editors have no Lepiter page context."
	^ nil
]

{ #category : 'actions' }
ElixirModuleCoder >> remove [
	"I delete my source file and purge the BEAM module.  The bridge's
	 `purge_module/1` broadcasts `:source_removed` on the bus, which
	 the stream reader fires through `BeamEventAnnouncer` so caches
	 (`BeamModuleResolution`, `BeamModuleSourceCache`) drop their
	 derived state.  No UI-side announce."
	sourcePath asFileReference ensureDelete.
	self application
		evaluateAndWait: 'GtBridge.HotReload.purge_module(', moduleName, ')'
]

{ #category : 'actions' }
ElixirModuleCoder >> saveAndCompile: newSource [
	"I write source to disk and trigger compile.  Bridge-side events
	 (`:source_written`, `:recompiled`, `:compile_failed`) flow through
	 `BeamEventStreamReader` and fire on `BeamEventAnnouncer` —
	 subscribers see them without me observing the HTTP response.

	 Preserves the original file's line ending convention and trailing
	 newline."
	| b64 normalized usesCrlf ending result |
	usesCrlf := self sourceCode includesSubstring: String crlf.
	ending := usesCrlf ifTrue: [ String crlf ] ifFalse: [ String lf ].
	normalized := newSource copyReplaceAll: String crlf with: String lf.
	normalized := normalized copyReplaceAll: String cr with: String lf.
	usesCrlf ifTrue: [
		normalized := normalized copyReplaceAll: String lf with: String crlf ].
	(normalized endsWith: ending) ifFalse: [
		normalized := normalized , ending ].
	b64 := ZnBase64Encoder new encode: normalized utf8Encoded.
	result := application newCommandFactory
		<< ('GtBridge.HotReload.reload("', sourcePath, '", Base.decode64!("', b64, '"))');
		sendAndWait.
	(result isKindOf: BeamBridgeEvalError) ifTrue: [
		Transcript
			show: 'ElixirModuleCoder >> saveAndCompile bridge error for ', moduleName, ': ';
			show: result printString;
			cr ].
	^ result
]

{ #category : 'accessing' }
ElixirModuleCoder >> selfObject [
	^ selfObject
]

{ #category : 'accessing' }
ElixirModuleCoder >> selfObject: anObject [
	selfObject := anObject
]

{ #category : 'accessing' }
ElixirModuleCoder >> sourceCode [
	"Return '' when the source file is gone (post-`remove` rebuilds
	 hit me before the coder pane is dismissed)."
	| ref |
	sourcePath ifNil: [ ^ '' ].
	ref := sourcePath asFileReference.
	^ ref exists ifTrue: [ ref contents ] ifFalse: [ '' ]
]

{ #category : 'accessing' }
ElixirModuleCoder >> sourcePath [
	^ sourcePath
]

{ #category : 'accessing' }
ElixirModuleCoder >> sourcePath: aString [
	sourcePath := aString
]

{ #category : 'actions' }
ElixirModuleCoder >> spliceFunction: newText forFunction: aName arity: anArity [
	"I find the function's current position in the file by name/arity,
	 splice the new text in, and save. Skips if a save is already running.

	 `functionEntries` short-circuits on the cache populated by the
	 most recent BeamModuleRecompiled, so back-to-back saves don't
	 each pay an `all_functions/1` round-trip."
	| match lines newLines st en |
	saving == true ifTrue: [ ^ self ].
	saving := true.
	[ match := self functionEntries
		detect: [ :e | (e attributeAt: #name) asString = aName
			and: [ (e attributeAt: #arity) = anArity ] ]
		ifNone: [ ^ self ].
	st := match attributeAt: #start.
	en := match attributeAt: #end_line.
	lines := self sourceCode lines.
	newLines := (lines copyFrom: 1 to: st - 1) asOrderedCollection.
	newLines addAll: newText lines.
	newLines addAll: (lines copyFrom: en + 1 to: lines size).
	self saveAndCompile: (String lf join: newLines) ]
	ensure: [ saving := false ]
]

{ #category : 'subscriptions' }
ElixirModuleCoder >> subscribeToEntries [
	"I subscribe (weakly) to the per-module cache's coarse
	 `BeamModuleEntriesUpdated` event — fired once per recompile
	 after the cache primes its entries list — and translate it
	 into my local `GtCoderSourceCodeChanged` for downstream
	 consumers (Source tab rebuild, streaming list)."
	(BeamEventAnnouncer for: moduleName) weak
		when: BeamModuleEntriesUpdated
		send: #onBeamModuleEntriesUpdated:
		to: self
]

{ #category : 'actions' }
ElixirModuleCoder >> swapFunctions: entryA with: entryB [
	"I swap two function blocks in the source, save, and compile."
	| lines startA endA startB endB blockA blockB newLines t |
	startA := entryA attributeAt: #start.
	endA := entryA attributeAt: #end_line.
	startB := entryB attributeAt: #start.
	endB := entryB attributeAt: #end_line.
	"Ensure A comes before B"
	startA > startB ifTrue: [
		t := startA. startA := startB. startB := t.
		t := endA. endA := endB. endB := t ].
	lines := self sourceCode lines.
	blockA := lines copyFrom: startA to: endA.
	blockB := lines copyFrom: startB to: endB.
	newLines := (lines copyFrom: 1 to: startA - 1),
		blockB,
		(lines copyFrom: endA + 1 to: startB - 1),
		blockA,
		(lines copyFrom: endB + 1 to: lines size).
	^ self saveAndCompile: (String lf join: newLines)
]

{ #category : 'subscriptions' }
ElixirModuleCoder >> unsubscribeFromEntries [
	"I drop my prior subscription before retargeting — otherwise I'd
	 leak listeners on the old module's announcer."
	moduleName ifNotNil: [
		(BeamEventAnnouncer for: moduleName) unsubscribe: self ]
]
