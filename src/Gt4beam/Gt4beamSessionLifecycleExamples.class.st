Class {
	#name : 'Gt4beamSessionLifecycleExamples',
	#superclass : 'Object',
	#instVars : [
		'sessionId'
	],
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
	self assert: (results anySatisfy: [ :r | r beginsWith: 'Enum.map/' ]).
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
		coderViewModel: viewModel;
		sessionId: self sessionId.
	^ strategy
]

{ #category : 'examples - bindings' }
Gt4beamSessionLifecycleExamples >> fetchedBindings [
	"I return the bindings dict from the target session.
	Exercises the /BINDINGS endpoint and deserialization."
	<gtExample>
	| bindings |
	self targetWithAccumulatedBindings.
	bindings := self target fetchBindingsWithSessionId: self sessionId.
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
	sessionId := [ | coder sid trigger |
		coder := self newCoder.
		sid := UUID new asString.
		coder bindAndExecuteRaw: 'x = 1' sessionId: sid.
		trigger := Object new.
		FinalizationRegistry default
			add: trigger
			finalizer: (BeamSessionFinalizer sessionId: sid application: app).
		sid ] value.
	before := self sessionCountVia: observer.
	Smalltalk garbageCollect.
	(Delay forMilliseconds: 100) wait.
	after := self sessionCountVia: observer.
	self assert: after < before.
	^ observer
]

{ #category : 'examples - views' }
Gt4beamSessionLifecycleExamples >> integerKeyedMapViews [
	"I verify all views render for a map with integer keys."
	<gtExample>
	| map |
	map := self target bindAndExecuteRaw: '%{1 => "one", 2 => "two"}'
		sessionId: self sessionId.
	self assertObjectPhlowViewsFor: map.
	^ map
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
	coder bindAndExecuteRaw: 'my_val = 2' sessionId: UUID new asString.
	v1 := self target bindAndExecuteRaw: 'my_val' sessionId: self sessionId.
	self assert: v1 equals: 1.
	^ coder
]

{ #category : 'private' }
Gt4beamSessionLifecycleExamples >> newCoder [
	"I create a fresh coder wired to the global application."
	| strategy coder |
	strategy := LeElixirApplicationStrategy new.
	coder := GtElixirCoderModel new.
	coder elixirLinkApplicationStrategy: strategy.
	^ coder
]

{ #category : 'examples - views' }
Gt4beamSessionLifecycleExamples >> pidViews [
	"I verify all views render for a PID."
	<gtExample>
	| pid |
	pid := self target bindAndExecuteRaw: 'self()'
		sessionId: self sessionId.
	self assertObjectPhlowViewsFor: pid.
	^ pid
]

{ #category : 'examples - cleanup' }
Gt4beamSessionLifecycleExamples >> sessionCloseRemovesSession [
	"I verify that POST /SESSION_CLOSE removes a session."

	<gtExample>
	| app target observer targetSid before after |
	app := self application.
	target := self newCoder.
	observer := self newCoder.
	targetSid := UUID new asString.
	target bindAndExecuteRaw: 'x = 1' sessionId: targetSid.
	before := self sessionCountVia: observer.
	self closeSessionId: targetSid on: app.
	after := self sessionCountVia: observer.
	self assert: after < before.
	^ observer
]

{ #category : 'private' }
Gt4beamSessionLifecycleExamples >> sessionCountVia: aCoder [
	"I query how many sessions exist in the EvalRegistry."
	^ aCoder bindAndExecuteRaw:
		'Registry.select(GtBridge.EvalRegistry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}]) |> length()'
		sessionId: self sessionId
]

{ #category : 'private' }
Gt4beamSessionLifecycleExamples >> sessionId [
	"I return a stable session UUID for this examples instance.
	Lazy-initialized so all examples on the same instance share one session."
	^ sessionId ifNil: [ sessionId := UUID new asString ]
]

{ #category : 'examples - views' }
Gt4beamSessionLifecycleExamples >> stringKeyedMapViews [
	"I verify all views render for a map with string keys."
	<gtExample>
	| map |
	map := self target bindAndExecuteRaw: '%{"hi" => "mom"}'
		sessionId: self sessionId.
	self assertObjectPhlowViewsFor: map.
	^ map
]

{ #category : 'examples - views' }
Gt4beamSessionLifecycleExamples >> structViews [
	"I verify all views render for a struct (has source)."
	<gtExample>
	| s |
	s := self target bindAndExecuteRaw: '%GtBridge.Eval{}'
		sessionId: self sessionId.
	self assertObjectPhlowViewsFor: s.
	^ s
]

{ #category : 'examples - setup' }
Gt4beamSessionLifecycleExamples >> target [
	"I return a coder with my_val bound to 1."
	<gtExample>
	| coder |
	coder := self newCoder.
	coder bindAndExecuteRaw: 'my_val = 1' sessionId: self sessionId.
	^ coder
]

{ #category : 'examples - documentation' }
Gt4beamSessionLifecycleExamples >> documentationSections [
	"I verify to_sections returns a delimited string."
	<gtExample>
	| sections |
	sections := self target bindAndExecuteRaw:
		'GtBridge.Documentation.to_sections(
			GtBridge.Documentation.for_module(Enum))'
		sessionId: self sessionId.
	self assert: (sections includesSubstring: '__SECTION__').
	^ sections
]

{ #category : 'examples - documentation' }
Gt4beamSessionLifecycleExamples >> functionDocumentation [
	"I return function-level docs for Enum.map/2."
	<gtExample>
	| doc |
	doc := self target bindAndExecuteRaw:
		'GtBridge.Documentation.for_function(Enum, :map, 2)'
		sessionId: self sessionId.
	self assertObjectPhlowViewsFor: doc.
	^ doc
]

{ #category : 'examples - documentation' }
Gt4beamSessionLifecycleExamples >> moduleAtomDocsView [
	"I verify a module atom has isModuleAtom and documentation renders."
	<gtExample>
	| atom |
	atom := self target bindAndExecuteRaw: 'Enum'
		sessionId: self sessionId.
	self assert: (atom isKindOf: BeamAtomObject).
	self assert: atom isModuleAtom.
	^ atom
]

{ #category : 'examples - documentation' }
Gt4beamSessionLifecycleExamples >> moduleDocumentation [
	"I return a Documentation proxy for Enum."
	<gtExample>
	| doc |
	doc := self target bindAndExecuteRaw:
		'GtBridge.Documentation.for_module(Enum)'
		sessionId: self sessionId.
	self assertObjectPhlowViewsFor: doc.
	^ doc
]
{ #category : 'examples - bindings' }
Gt4beamSessionLifecycleExamples >> targetWithAccumulatedBindings [
	"I return the target coder after accumulating more bindings.
	Proves bindings persist across evals within a session."
	<gtExample>
	| coder y |
	coder := self target.
	coder bindAndExecuteRaw: 'y = my_val + 1' sessionId: self sessionId.
	y := coder bindAndExecuteRaw: 'y' sessionId: self sessionId.
	self assert: y equals: 2.
	^ coder
]
