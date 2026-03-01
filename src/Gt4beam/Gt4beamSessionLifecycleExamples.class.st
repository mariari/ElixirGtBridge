Class {
	#name : 'Gt4beamSessionLifecycleExamples',
	#superclass : 'Object',
	#category : 'Gt4beam-Examples',
	#package : 'Gt4beam',
	#tag : 'Examples'
}

{ #category : 'examples - setup' }
Gt4beamSessionLifecycleExamples >> application [
	"I start a fresh BeamLinkApplication."
	<gtExample>
	| app |
	app := BeamLinkApplication start.
	self assert: app isRunning.
	^ app
]

{ #category : 'private' }
Gt4beamSessionLifecycleExamples >> closeSessionId: aSessionId on: anApp [
	"I send POST /SESSION_CLOSE for the given sessionId."
	| serverAddress url |
	serverAddress := anApp settings serverSocketAddress.
	url := 'http://' , serverAddress ipOrName , ':'
		, serverAddress port asString , '/SESSION_CLOSE'.
	^ ZnClient new
		url: url;
		entity: (ZnEntity
			with: (STONJSON toString: { #sessionId -> aSessionId } asDictionary)
			type: ZnMimeType applicationJson);
		post
]

{ #category : 'examples - completion' }
Gt4beamSessionLifecycleExamples >> completeModuleDot [
	"I complete 'Enum.ma' and return the results.
	Exercises module function completion via /COMPLETE."
	<gtExample>
	| results |
	results := self completionStrategy fetchCompletionsFor: 'Enum.ma'.
	self assert: (results includes: 'Enum.map').
	^ results
]

{ #category : 'examples - completion' }
Gt4beamSessionLifecycleExamples >> completeWithBindings [
	"I complete a variable prefix using session bindings.
	The target has my_val bound; completing 'my_' finds it."
	<gtExample>
	| results |
	results := self completionStrategy fetchCompletionsFor: 'my_'.
	self assert: (results includes: 'my_val').
	^ results
]

{ #category : 'examples - completion' }
Gt4beamSessionLifecycleExamples >> completionStrategy [
	"I return a completion strategy wired to the target session."
	<gtExample>
	| viewModel strategy |
	viewModel := self target asCoderViewModel.
	strategy := GtElixirCompletionStrategy new.
	strategy
		coderModel: self target;
		coderViewModel: viewModel.
	^ strategy
]

{ #category : 'examples - bindings' }
Gt4beamSessionLifecycleExamples >> fetchedBindings [
	"I return the bindings dict from the target session.
	Exercises the /BINDINGS endpoint and deserialization."
	<gtExample>
	| bindings |
	self targetWithAccumulatedBindings.
	bindings := self target fetchBindings.
	self assert: (bindings includesKey: #my_val).
	^ bindings
]

{ #category : 'examples - cleanup' }
Gt4beamSessionLifecycleExamples >> gcCleansUpSession [
	"I verify that GC of the finalizer target fires SESSION_CLOSE.
	A block creates the session and registers the finalizer on a
	local object — when the block returns, it goes out of scope."

	<gtExample>
	| app observer sessionId before after |
	app := self application.
	observer := self newCoder.
	sessionId := [ | coder trigger |
		coder := self newCoder.
		coder bindAndExecuteRaw: 'x = 1'.
		trigger := Object new.
		FinalizationRegistry default
			add: trigger
			finalizer: (BeamSessionFinalizer sessionId: coder sessionId application: app).
		coder sessionId ] value.
	before := self sessionCountVia: observer.
	Smalltalk garbageCollect.
	(Delay forMilliseconds: 50) wait.
	after := self sessionCountVia: observer.
	self assert: after < before.
	^ observer
]

{ #category : 'examples - encoding' }
Gt4beamSessionLifecycleExamples >> message [
	"I return a base enqueue message. Without a sessionId,
	encoding omits the key (backward-compatible default)."
	<gtExample>
	| msg |
	msg := ElixirLinkEnqueueCommandMessage new
		commandId: 'cmd-1';
		statements: 'x = 1'.
	self assert: (msg encode includesKey: #sessionId) not.
	^ msg
]

{ #category : 'examples - encoding' }
Gt4beamSessionLifecycleExamples >> messageWithSessionId [
	"I add a sessionId to the base message.
	Encoding now includes it (per-page path)."
	<gtExample>
	| msg |
	msg := self message.
	msg sessionId: 'page-abc'.
	self assert: (msg encode at: #sessionId) equals: 'page-abc'.
	^ msg
]

{ #category : 'examples - sessions' }
Gt4beamSessionLifecycleExamples >> myVal2SessionIsolated [
	"I return a second coder with my_val bound to 2,
	isolated from the target."
	<gtExample>
	| coder v1 |
	coder := self newCoder.
	coder bindAndExecuteRaw: 'my_val = 2'.
	v1 := self target bindAndExecuteRaw: 'my_val'.
	self assert: v1 equals: 1.
	^ coder
]

{ #category : 'private' }
Gt4beamSessionLifecycleExamples >> newCoder [
	"I create a fresh coder wired to the global application
	with a unique sessionId."
	| strategy coder |
	strategy := LeElixirApplicationStrategy new.
	coder := GtElixirCoderModel new.
	coder
		elixirLinkApplicationStrategy: strategy;
		sessionId: UUID new asString.
	^ coder
]

{ #category : 'examples - cleanup' }
Gt4beamSessionLifecycleExamples >> sessionCloseRemovesSession [
	"I verify that POST /SESSION_CLOSE removes a session."

	<gtExample>
	| app target observer before after |
	app := self application.
	target := self newCoder.
	observer := self newCoder.
	target bindAndExecuteRaw: 'x = 1'.
	before := self sessionCountVia: observer.
	self closeSessionId: target sessionId on: app.
	after := self sessionCountVia: observer.
	self assert: after < before.
	^ observer
]

{ #category : 'private' }
Gt4beamSessionLifecycleExamples >> sessionCountVia: aCoder [
	"I query how many sessions exist in the EvalRegistry."
	^ aCoder bindAndExecuteRaw:
		'Registry.select(GtBridge.EvalRegistry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}]) |> length()'
]

{ #category : 'examples - setup' }
Gt4beamSessionLifecycleExamples >> target [
	"I return a coder with my_val bound to 1."
	<gtExample>
	| coder |
	coder := self newCoder.
	coder bindAndExecuteRaw: 'my_val = 1'.
	^ coder
]

{ #category : 'examples - bindings' }
Gt4beamSessionLifecycleExamples >> targetWithAccumulatedBindings [
	"I return the target coder after accumulating more bindings.
	Proves bindings persist across evals within a session."
	<gtExample>
	| coder y |
	coder := self target.
	coder bindAndExecuteRaw: 'y = my_val + 1'.
	y := coder bindAndExecuteRaw: 'y'.
	self assert: y equals: 2.
	^ coder
]
