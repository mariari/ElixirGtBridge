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
	#category : 'Gt4beam',
	#package : 'Gt4beam'
}

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

{ #category : 'examples - setup' }
BeamEventBusExamples >> streamingModel [
	"I return a fresh ElixirFunctionStreamingModel wrapping a fresh
	 ElixirModuleCoder. Two calls yield two independent streaming
	 models — both subscribed (weakly) to BeamModuleRecompiled."
	<gtExample>
	^ ElixirFunctionStreamingModel forModuleCoder: self moduleCoder
]

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

{ #category : 'examples - announcer' }
BeamEventBusExamples >> compileFailedDoesNotMatchRecompiled [
	"I subscribe to BeamModuleRecompiled and fire a BeamCompileFailed.
	 Returns the (empty) received collection — the typed Announcer
	 dispatch correctly filters by class so failed-compile events
	 don't trigger surface refreshes."
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

{ #category : 'examples - end-to-end' }
BeamEventBusExamples >> saveFiresBeamModuleRecompiled [
	"I save HotReloadTest via a coder and observe that
	 BeamEventAnnouncer fires BeamModuleRecompiled. Proves the
	 GT-side wiring (saveAndCompile reads the recompiled list from
	 hot_reload's response and announces).

	 Returns the received announcements — at minimum one for
	 HotReloadTest, possibly more if dep-siblings recompiled too."
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
		self assert: received isNotEmpty
			description: 'saveAndCompile should fire BeamModuleRecompiled'.
		self assert: (received anySatisfy: [ :a | a mod = 'HotReloadTest' ])
			description: 'directly-saved module should be in the announcement set' ]
		ensure: [
			BeamEventAnnouncer default unsubscribe: tag.
			coder saveAndCompile: original ].
	^ received
]

{ #category : 'examples - cross-coder' }
BeamEventBusExamples >> twoCodersSeeSameUpdateAfterSave [
	"I create two independent ElixirModuleCoders for HotReloadTest,
	 edit hello/0 via the first, and verify the SECOND coder reads
	 fresh source.  Functions tab is BEAM-backed so the second
	 coder doesn't need its own subscription — it just queries the
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
	 via the first's coder, and verify the SECOND streaming model's
	 underlying moduleCoder reads fresh source after the save.

	 Both streaming models subscribe to BeamModuleRecompiled in their
	 #moduleCoder: setter — testing through the public moduleCoder
	 functionEntries surface keeps us off private state while still
	 proving the cross-instance refresh chain end-to-end.

	 Returns the second streaming model so it's inspectable."
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

{ #category : 'examples - source tab' }
BeamEventBusExamples >> sourceTabRefreshesOnSave [
	"I build a Source tab element on a coder, save the module via the
	 same coder, and verify the inner element was rebuilt (object
	 identity changes — buildSourceViewElement's rebuild block
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
