"
I am a collection of examples covering the BEAM event bus end-to-end:
EventBroker → CacheReaper invalidation → HTTP response payload →
BeamEventAnnouncer → GT subscribers.

Examples compose: `moduleCoder` returns a fresh ElixirModuleCoder
for HotReloadTest; calling it twice yields two independent coder
instances against the same module, which is exactly what cross-coder
sync verification needs.

Sources are restored after every save via `ensure:` so examples can
be re-run.
"
Class {
	#name : 'BeamEventBusExamples',
	#superclass : 'Object',
	#category : 'Gt4beam-Examples',
	#package : 'Gt4beam',
	#tag : 'Examples'
}

{ #category : 'examples - announcer' }
BeamEventBusExamples >> announcerDeliversTypedAnnouncement [
	"I subscribe a tag to BeamModuleRecompiled, fire one, and
	 assert it arrives with intact mod and sourceHash. Pure dispatch
	 test — no save, no BEAM round-trip."
	<gtExample>
	| tag received |
	tag := Object new.
	received := nil.
	BeamEventAnnouncer default
		when: BeamModuleRecompiled
		do: [ :a | received := a ]
		for: tag.
	BeamEventAnnouncer default announce:
		(BeamModuleRecompiled mod: 'HotReloadTest' sourceHash: 42).
	BeamEventAnnouncer default unsubscribe: tag.
	self assert: received notNil description: 'announcement should arrive'.
	self assert: received mod equals: 'HotReloadTest'.
	self assert: received sourceHash equals: 42.
	^ received
]

{ #category : 'examples - browser' }
BeamEventBusExamples >> browserRawNodesInvalidatesOnSave [
	"I assert ElixirCoderBrowser drops its rawNodes cache when a
	 module recompiles.  Without this the sidebar shows the module
	 set from when the browser opened, so module-detail changes
	 (function count, doc presence) stay invisible until close +
	 reopen."

	<gtExample>
	| browser scripter before path coder original |
	browser := ElixirCoderBrowser new
		application: BeamLinkApplication uniqueInstance;
		scopedApplicationName: 'hot_reload_test';
		yourself.
	scripter := BlScripter new
		element: browser;
		yourself.
	scripter wait forEmptySpaceTaskQueue.

	"Force the lazy rawNodes to populate."
	before := browser rawNodes.
	self assert: before isNotNil.

	"Trigger a real BeamModuleRecompiled via a no-op save."
	path := BeamLinkApplication uniqueInstance evaluateAndWait:
		'GtBridge.Resolve.source_file(HotReloadTest)'.
	coder := ElixirModuleCoder new
		application: BeamLinkApplication uniqueInstance;
		moduleName: 'HotReloadTest';
		sourcePath: path;
		yourself.
	original := coder sourceCode.
	coder saveAndCompile: original.
	self waitFor: [ browser rawNodes ~~ before ].

	self assert: browser rawNodes ~~ before
		description: 'rawNodes should be re-fetched after BeamModuleRecompiled'.
	^ browser
]

{ #category : 'examples - announcer' }
BeamEventBusExamples >> compileFailedDoesNotMatchRecompiled [
	"I subscribe to BeamModuleRecompiled and fire a BeamCompileFailed.
	 Returns the (empty) received collection — the typed Announcer
	 dispatch correctly filters by class so failed-compile events
	 do not trigger surface refreshes."
	<gtExample>
	| tag received |
	tag := Object new.
	received := OrderedCollection new.
	BeamEventAnnouncer default
		when: BeamModuleRecompiled
		do: [ :a | received add: a ]
		for: tag.
	BeamEventAnnouncer default announce:
		(BeamCompileFailed mod: 'HotReloadTest' errors: #()).
	BeamEventAnnouncer default unsubscribe: tag.
	self assert: received isEmpty.
	^ received
]

{ #category : 'examples - announcer' }
BeamEventBusExamples >> dispatchHitsBothNarrowAndWildcard [
	"I subscribe one tag to the per-module announcer for 'Foo' and
	 another to the default singleton, fire one event for 'Foo', and
	 assert BOTH receive it. Confirms the dispatcher entry point fans
	 out to both channels rather than picking one."
	<gtExample>
	| narrowTag wildcardTag narrowReceived wildcardReceived |
	narrowTag := Object new.
	wildcardTag := Object new.
	narrowReceived := OrderedCollection new.
	wildcardReceived := OrderedCollection new.
	(BeamEventAnnouncer for: 'Foo')
		when: BeamModuleRecompiled
		do: [ :a | narrowReceived add: a mod ]
		for: narrowTag.
	BeamEventAnnouncer default
		when: BeamModuleRecompiled
		do: [ :a | wildcardReceived add: a mod ]
		for: wildcardTag.
	BeamEventAnnouncer announceRecompiled: 'Foo'.
	(BeamEventAnnouncer for: 'Foo') unsubscribe: narrowTag.
	BeamEventAnnouncer default unsubscribe: wildcardTag.
	self assert: narrowReceived asArray equals: #('Foo').
	self assert: wildcardReceived asArray equals: #('Foo').
	^ { narrowReceived. wildcardReceived }
]

{ #category : 'examples - end-to-end UI' }
BeamEventBusExamples >> functionsTabUpdatesOnSaveViaScripter [
	"I script the full real-world chain end-to-end:

	 1. Build an ElixirModuleCoder via the INSPECTOR path (prefixed
	    'Elixir.HotReloadTest' name) — same code path the bug came in on.
	 2. Build the Functions tab element from that coder.
	 3. Wrap in a BlScripter so the element gets a real BlSpace and the
	    async streams resolve.
	 4. Trigger a save via the model API.
	 5. Wait for the deferred tasks the announcement chain enqueues.
	 6. Assert the streaming view model received the GtStreamingCodersStreamChanged
	    that buildSourceViewElement / refreshStream produces — proving the
	    chain reached refreshStream and not just the announcer.

	 If the prefix-stripping regresses OR onBeamModuleRecompiled stops
	 calling refreshStream, the received collection stays empty and this
	 example goes red."
	<gtExample>
	| coder path element scripter sm received original markerSource |
	path := BeamLinkApplication uniqueInstance evaluateAndWait:
		'GtBridge.Resolve.source_file(HotReloadTest)'.
	self assert: path isNotNil description: 'HotReloadTest must be loaded'.

	"Note the prefixed name — same as the real inspector path"
	coder := ElixirModuleCoder new
		application: BeamLinkApplication uniqueInstance;
		moduleName: 'Elixir.HotReloadTest';
		sourcePath: path;
		yourself.
	self assert: coder moduleName equals: 'HotReloadTest'.

	element := coder buildFunctionsViewElement.
	scripter := BlScripter new
		element: element;
		yourself.
	scripter wait forEmptySpaceTaskQueue.

	"buildFunctionsViewElement returns a container whose second child
	 is the ElixirFunctionStreamingElement — find it and walk to the model."
	sm := (element children
		detect: [ :c | c isKindOf: ElixirFunctionStreamingElement ])
		streamingCodersViewModel streamingCodersModel.
	received := OrderedCollection new.
	sm
		when: GtStreamingCodersStreamChanged
		do: [ :a | received add: a ]
		for: #scripterTap.

	original := coder sourceCode.
	"Insert a new def INSIDE the module (before the closing 'end')."
	markerSource := original
		copyReplaceAll: 'def hello, do: :world'
		with: 'def hello, do: :world
  def added_via_scripter, do: :ok'.

	[ coder saveAndCompile: markerSource.
		scripter wait forEmptySpaceTaskQueue.
		self assert: received isNotEmpty
			description: 'save should reach refreshStream and fire GtStreamingCodersStreamChanged' ]
		ensure: [
			sm unsubscribe: #scripterTap.
			coder saveAndCompile: original ].

	^ scripter
]

{ #category : 'examples - setup' }
BeamEventBusExamples >> moduleCoder [
	"I return a fresh ElixirModuleCoder wired to the HotReloadTest
	 fixture dep.  Each call returns a new instance — calling me
	 twice yields two independent subscribers against the same
	 module, the basis for cross-coder sync verification."
	<gtExample>
	| app coder path |
	app := BeamLinkApplication uniqueInstance.
	path := app evaluateAndWait: 'GtBridge.Resolve.source_file(HotReloadTest)'.
	self assert: path isNotNil description: 'HotReloadTest must be loaded'.
	coder := ElixirModuleCoder new.
	coder application: app.
	coder moduleName: 'HotReloadTest'.
	coder sourcePath: path.
	self assert: coder hasFunctions.
	^ coder
]

{ #category : 'examples - module-name normalization' }
BeamEventBusExamples >> moduleNamePrefixIsStrippedOnInput [
	"I assert that ElixirModuleCoder canonicalises moduleName to the
	 bare form regardless of whether the caller passes the raw atom
	 string ('Elixir.Foo.Bar') or the bare name ('Foo.Bar').

	 Without this normalisation, BeamModuleRecompiled events (which
	 always carry the bare form) silently never match coders built
	 by the inspector path (which passes the prefixed form), and
	 every open Functions tab stays stale on save. Lock it in."
	<gtExample>
	| prefixed bare |
	prefixed := ElixirModuleCoder new
		moduleName: 'Elixir.Foo.Bar';
		yourself.
	bare := ElixirModuleCoder new
		moduleName: 'Foo.Bar';
		yourself.
	self assert: prefixed moduleName equals: 'Foo.Bar'.
	self assert: bare moduleName equals: 'Foo.Bar'.
	self assert: prefixed moduleName equals: bare moduleName.
	^ { prefixed. bare }
]

{ #category : 'examples - announcer' }
BeamEventBusExamples >> narrowSubscriberOnlyHearsItsModule [
	"I subscribe to the per-module announcer for 'Foo', fire dispatch
	 events for both 'Foo' and 'Bar', and assert only Foo arrives.
	 Proves the per-module routing actually filters at publish time —
	 not just hides events with a guard in the handler."
	<gtExample>
	| tag received |
	tag := Object new.
	received := OrderedCollection new.
	(BeamEventAnnouncer for: 'Foo')
		when: BeamModuleRecompiled
		do: [ :a | received add: a mod ]
		for: tag.
	BeamEventAnnouncer announceRecompiled: 'Foo'.
	BeamEventAnnouncer announceRecompiled: 'Bar'.
	BeamEventAnnouncer announceRecompiled: 'Foo'.
	(BeamEventAnnouncer for: 'Foo') unsubscribe: tag.
	self assert: received asArray equals: #('Foo' 'Foo').
	^ received
]

{ #category : 'examples - source tab' }
BeamEventBusExamples >> peerSourceTabRefreshesOnSave [
	"I build a Source tab on coder1, save via coder2 (different
	 instance, same module), and verify coder1's Source tab was
	 rebuilt — proving cross-instance Source-tab refresh works."
	<gtExample>
	| coder1 coder2 original markerSource container childBefore childAfter |
	coder1 := self moduleCoder.
	coder2 := self moduleCoder.
	container := coder1 buildSourceViewElement.
	childBefore := container children first.
	original := coder1 sourceCode.
	markerSource := original copyReplaceAll: ':world' with: ':peerRefresh'.
	[ coder2 saveAndCompile: markerSource.
		childAfter := container children first.
		self assert: childBefore ~~ childAfter
			description: 'Source tab on peer coder should rebuild on cross-instance save' ]
		ensure: [ coder1 saveAndCompile: original ].
	^ container
]

{ #category : 'examples - payload' }
BeamEventBusExamples >> recompileEventCarriesFunctionsInline [
	"I assert that BeamModuleRecompiled for the directly-saved module
	 arrives with `functions` populated.  Subscribers can then read
	 the new entries from the announcement payload directly instead
	 of round-tripping `Analysis.all_functions/1` per consumer."

	<gtExample>
	| coder original tag received |
	coder := self moduleCoder.
	original := coder sourceCode.
	tag := Object new.
	received := OrderedCollection new.
	(BeamEventAnnouncer for: 'HotReloadTest')
		when: BeamModuleRecompiled
		do: [ :a | received add: a ]
		for: tag.
	[ coder saveAndCompile: original.
	  self waitFor: [ received isNotEmpty ] ]
		ensure: [ (BeamEventAnnouncer for: 'HotReloadTest') unsubscribe: tag ].
	self assert: received isNotEmpty
		description: 'save should fire BeamModuleRecompiled for HotReloadTest'.
	self assert: received first functions isNotNil
		description: 'directly-saved module announcement should carry function entries'.
	self assert: received first functions asArray isNotEmpty
		description: 'function entries should be non-empty for HotReloadTest'.
	^ received first
]

{ #category : 'examples - payload' }
BeamEventBusExamples >> saveCachesFunctionEntriesOnCoder [
	"I assert that after saveAndCompile, the per-module
	 `BeamModuleSourceCache` holds the freshly-compiled entries —
	 the next `coder functionEntries` call returns the cache list
	 without a bridge round-trip.

	 Concrete proof of the FRP win: the recompile event primes the
	 cache via `BeamModuleSourceCache>>onBeamModuleRecompiled:`;
	 `coder functionEntries` reads from it instead of round-tripping
	 `Analysis.all_functions/1`."
	<gtExample>
	| coder original cache entriesAfter |
	coder := self moduleCoder.
	original := coder sourceCode.
	cache := BeamModuleSourceCache for: 'HotReloadTest'.
	"Make sure the cache starts empty so we observe the side-effect."
	cache clear.
	[ coder saveAndCompile: original ]
		ensure: [ coder saveAndCompile: original ].
	self assert: cache entries isNotEmpty
		description: 'save should populate per-module cache via announcement payload'.
	"And `functionEntries` returns the cache list — same identity,
	 no bridge call."
	entriesAfter := coder functionEntries.
	self assert: entriesAfter == cache entries
		description: 'functionEntries should return the cache list, not refetch'.
	^ coder
]

{ #category : 'examples - end-to-end' }
BeamEventBusExamples >> saveFiresBeamModuleRecompiled [
	"I save HotReloadTest via a coder and observe that
	 BeamEventAnnouncer fires BeamModuleRecompiled.  Returns the
	 received announcements (at minimum one for HotReloadTest,
	 possibly more if dep-siblings recompiled too)."

	<gtExample>
	| coder original tag received markerSource |
	coder := self moduleCoder.
	original := coder sourceCode.
	markerSource := original copyReplaceAll: ':world' with: ':saveFires'.
	tag := Object new.
	received := OrderedCollection new.
	BeamEventAnnouncer default
		when: BeamModuleRecompiled
		do: [ :a | received add: a ]
		for: tag.
	[ coder saveAndCompile: markerSource.
	  self waitFor: [ received anySatisfy: [ :a | a mod = 'HotReloadTest' ] ].
	  self assert: received isNotEmpty
			description: 'saveAndCompile should fire BeamModuleRecompiled'.
	  self assert: (received anySatisfy: [ :a | a mod = 'HotReloadTest' ])
			description: 'directly-saved module should be in the announcement set' ]
		ensure: [
			BeamEventAnnouncer default unsubscribe: tag.
			coder saveAndCompile: original ].
	^ received
]

{ #category : 'examples - source tab' }
BeamEventBusExamples >> sourceTabRefreshesOnSave [
	"I build a Source tab element on a coder, save the module via the
	 same coder, and verify the inner element was rebuilt (object
	 identity changes — buildSourceViewElement rebuild block
	 removeChildren + addChild a new one)."
	<gtExample>
	| coder original markerSource container childBefore childAfter |
	coder := self moduleCoder.
	container := coder buildSourceViewElement.
	childBefore := container children first.
	original := coder sourceCode.
	markerSource := original copyReplaceAll: ':world' with: ':sourceTabRefresh'.
	[ coder saveAndCompile: markerSource.
		childAfter := container children first.
		self assert: childBefore ~~ childAfter
			description: 'Source tab inner element should be rebuilt on save' ]
		ensure: [ coder saveAndCompile: original ].
	^ container
]

{ #category : 'examples - setup' }
BeamEventBusExamples >> streamingModel [
	"I return a fresh ElixirFunctionStreamingModel wrapping a fresh
	 ElixirModuleCoder. Two calls yield two independent streaming
	 models — both subscribed (weakly) to BeamModuleRecompiled."
	<gtExample>
	^ ElixirFunctionStreamingModel forModuleCoder: self moduleCoder
]

{ #category : 'examples - cross-coder' }
BeamEventBusExamples >> twoCodersSeeSameUpdateAfterSave [
	"I create two independent ElixirModuleCoders for HotReloadTest,
	 edit hello/0 via the first, and verify the SECOND coder reads
	 fresh source.  Functions tab is BEAM-backed so the second
	 coder does not need its own subscription — it just queries the
	 BEAM, whose ETS cache is invalidated by CacheReaper.

	 Returns a Dictionary with both coders so callers can inspect
	 in the GT inspector."
	<gtExample>
	| coder1 coder2 original markerSource entry |
	coder1 := self moduleCoder.
	coder2 := self moduleCoder.
	original := coder1 sourceCode.
	markerSource := original copyReplaceAll: ':world' with: ':twoCoders'.
	[ coder1 saveAndCompile: markerSource.
		entry := coder2 functionEntries detect: [ :e |
			(e attributeAt: #name) asString = 'hello' ].
		self assert: ((entry attributeAt: #source) asString
			includesSubstring: ':twoCoders')
			description: 'second coder should observe the first coder''s save' ]
		ensure: [ coder1 saveAndCompile: original ].
	^ Dictionary new
		at: 'coder1' put: coder1;
		at: 'coder2' put: coder2;
		yourself
]

{ #category : 'examples - cross-coder' }
BeamEventBusExamples >> twoStreamingModelsBothRefresh [
	"I create two independent streaming models for HotReloadTest, save
	 via the first coder, and verify the SECOND streaming model
	 underlying moduleCoder reads fresh source after the save.

	 Both streaming models subscribe to BeamModuleRecompiled in their
	 #moduleCoder: setter — testing through the public moduleCoder
	 functionEntries surface keeps us off private state while still
	 proving the cross-instance refresh chain end-to-end.

	 Returns the second streaming model so it is inspectable."
	<gtExample>
	| sm1 sm2 original markerSource entry |
	sm1 := self streamingModel.
	sm2 := self streamingModel.
	original := sm1 moduleCoder sourceCode.
	markerSource := original copyReplaceAll: ':world' with: ':streamSync'.
	[ sm1 moduleCoder saveAndCompile: markerSource.
		entry := sm2 moduleCoder functionEntries detect: [ :e |
			(e attributeAt: #name) asString = 'hello' ].
		self assert: ((entry attributeAt: #source) asString
			includesSubstring: ':streamSync')
			description: 'sm2''s moduleCoder should observe the save via fresh BEAM data' ]
		ensure: [ sm1 moduleCoder saveAndCompile: original ].
	^ sm2
]

{ #category : 'private' }
BeamEventBusExamples >> waitFor: aBlock [
	"Poll `aBlock` until it returns truthy or 2s elapses.  Bridges the
	 SSE-delivery gap between `coder saveAndCompile:` returning and
	 the BeamModuleRecompiled subscriber receiving."
	| deadline |
	deadline := DateAndTime now + 2 seconds.
	[ aBlock value or: [ DateAndTime now > deadline ] ] whileFalse: [
		(Delay forMilliseconds: 20) wait ]
]

{ #category : 'examples - announcer' }
BeamEventBusExamples >> wildcardOnDefaultHearsEveryModule [
	"I subscribe to the default singleton (wildcard channel) and fire
	 events for two different modules. Both should arrive — that's
	 what the default channel exists for (browser, etc.)."
	<gtExample>
	| tag received |
	tag := Object new.
	received := OrderedCollection new.
	BeamEventAnnouncer default
		when: BeamModuleRecompiled
		do: [ :a | received add: a mod ]
		for: tag.
	BeamEventAnnouncer announceRecompiled: 'Foo'.
	BeamEventAnnouncer announceRecompiled: 'Bar'.
	BeamEventAnnouncer default unsubscribe: tag.
	self assert: received asArray equals: #('Foo' 'Bar').
	^ received
]
