Class {
	#name : 'GtElixirCoderModel',
	#superclass : 'GtSourceCoder',
	#traits : 'TElixirNavigationCoder',
	#classTraits : 'TElixirNavigationCoder classTrait',
	#instVars : [
		'application',
		'elixirLinkApplicationStrategy',
		'primedSessions',
		'contextModuleName',
		'pageAliasSources'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'accessing' }
GtElixirCoderModel >> application [

	"I return the BEAM application, initializing it if needed."

	application ifNil: [ self initializeApplication ].
	^ application
]

{ #category : 'converting' }
GtElixirCoderModel >> asCoderViewModel [
	^ GtElixirSnippetCoderViewModel new coder: self
]

{ #category : 'accessing' }
GtElixirCoderModel >> bindAndExecute: sourceString inContext: aContext sessionId: sid [
	"I prime the session with self's module context once, prepend the
	 self binding, then eval."
	| selfObj |
	selfObj := self selfObjectFor: aContext.
	self initializeApplication.
	self ensureSessionPrimed: selfObj sessionId: sid.
	^ self
		bindAndExecuteRaw: (self wrapSource: sourceString withSelf: selfObj)
		sessionId: sid
]

{ #category : 'accessing' }
GtElixirCoderModel >> bindAndExecuteRaw: sourceString sessionId: sid [
	| factory |
	self initializeApplication.
	factory := application newCommandFactory.
	sid ifNotNil: [ factory sessionId: sid ].
	^ factory
		<< sourceString;
		sendAndWait
]

{ #category : 'accessing' }
GtElixirCoderModel >> computeAst: theSourceString [
	^ ElixirParser
		parseWithErrors: theSourceString
]

{ #category : 'accessing' }
GtElixirCoderModel >> contextModuleName [
	^ contextModuleName
]

{ #category : 'accessing' }
GtElixirCoderModel >> contextModuleName: aString [
	contextModuleName := aString
]

{ #category : 'private' }
GtElixirCoderModel >> doFetchBindingsWithSessionId: sid [
	"Bindings go over the framed transport as a BINDINGS request.  The
	 reader's deserializer already reifies proxy values (the one-decoder
	 path), so the resolved dictionary is the reified result."
	| payload result |
	application ifNil: [ ^ Dictionary new ].
	payload := Dictionary new.
	payload at: 'type' put: 'BINDINGS'.
	sid ifNotNil: [ payload at: 'sessionId' put: sid ].
	result := [ application executionHandler requestAndWait: payload ]
		on: Error do: [ Dictionary new ].
	^ (result isKindOf: Dictionary) ifTrue: [ result ] ifFalse: [ Dictionary new ]
]

{ #category : 'accessing' }
GtElixirCoderModel >> elixirLinkApplicationStrategy: anApplicationStrategy [
	elixirLinkApplicationStrategy := anApplicationStrategy
]

{ #category : 'private' }
GtElixirCoderModel >> ensureSessionFinalizerFor: viewBindings sessionId: sid coderViewModel: aCoderVM [
	aCoderVM ifNil: [ ^ self ].
	aCoderVM sessionFinalizerRegistered ifTrue: [ ^ self ].
	viewBindings ifNil: [ ^ self ].
	sid ifNil: [ ^ self ].
	FinalizationRegistry default
		add: viewBindings
		finalizer: (BeamSessionFinalizer
			sessionId: sid
			application: application).
	aCoderVM sessionFinalizerRegistered: true
]

{ #category : 'private' }
GtElixirCoderModel >> ensureSessionPrimed: selfObj sessionId: sid [
	"I load self's module context (its import plus alias/import/require
	 directives) into the eval session env, server-side, once per
	 session. Env persists across a session's evals, so snippets travel
	 unwrapped. Session-less evals run stateless on the bridge
	 (Tcp.Dispatch), where priming cannot stick; they go unprimed."
	| modName key |
	sid ifNil: [ ^ self ].
	modName := (selfObj respondsTo: #elixirClass)
		ifTrue: [ selfObj elixirClass ]
		ifFalse: [ nil ].
	modName ifNil: [ ^ self ].
	key := sid , '|' , modName.
	primedSessions ifNil: [ primedSessions := Set new ].
	(primedSessions includes: key) ifTrue: [ ^ self ].
	application evaluateAndWait:
		'GtBridge.Eval.Preamble.editor_session(' , modName , ', "' , sid , '")'.
	primedSessions add: key
]

{ #category : 'private' }
GtElixirCoderModel >> fetchBindingsWithSessionId: sid [
	^ [ self doFetchBindingsWithSessionId: sid ] on: Error do: [ Dictionary new ]
]

{ #category : 'accessing' }
GtElixirCoderModel >> initializeAddOns: addOns [
	super initializeAddOns: addOns.

	addOns
		addStyler: (GtCoderAstSmaCCParserStyler new smaccStyler: ElixirParser gtStyler).
	addOns
		addStyler: ElixirFunctionExpanderStyler new.

	elixirLinkApplicationStrategy
		ifNotNil: [ addOns
				addMainAction: 'Inspect' translated
				icon: BrGlamorousVectorIcons playinspect
				action: [ :aCoderUIModel :anElement |
					GtCoderCodeExecutor doItAndGo
						coderViewModel: aCoderUIModel;
						element: anElement;
						execute ]
				id: GtSourceCoderDoItAndGoActionId.
			addOns
				addMainAction: 'Evaluate' translated
				icon: BrGlamorousVectorIcons play
				action: [ :aCoderUIModel :anElement |
					GtCoderCodeExecutor doIt
						coderViewModel: aCoderUIModel;
						element: anElement;
						execute ]
				id: GtSourceCoderDoItActionId ]
]

{ #category : 'accessing' }
GtElixirCoderModel >> initializeApplication [
	application := elixirLinkApplicationStrategy applicationServer.
	application isRunning ifFalse: [ application start ].
	^ application
]

{ #category : 'accessing' }
GtElixirCoderModel >> initializeShortcuts: addOns [
	"Register unconditionally — Lepiter snippets set the strategy
	 after addOns init, so an `ifNotNil:` guard would skip them."
	super initializeShortcuts: addOns.
	addOns
		addShortcut: GtSourceCoderDoItShortcut new;
		addShortcut: GtSourceCoderDoItAndInspectShortcut new;
		addShortcut: GtSourceCoderSaveShortcut new;
		addShortcut: ElixirCoderFormatShortcut new.
	self initializeNavigationShortcuts: addOns
]

{ #category : 'accessing' }
GtElixirCoderModel >> newCompletionStrategy [
	^ GtCompletionStrategy new
]

{ #category : 'accessing' }
GtElixirCoderModel >> pageAliasSources [
	"Sibling snippets' sources, one string each, whose `alias`/`import`
	 lines also resolve module references in this coder."
	^ pageAliasSources ifNil: [ #(  ) ]
]

{ #category : 'accessing' }
GtElixirCoderModel >> pageAliasSources: aCollection [
	pageAliasSources := aCollection
]

{ #category : 'accessing' }
GtElixirCoderModel >> primitiveEvaluate: aSourceString inContext: aContext onFailDo: anEvaluationFailBlock [
	| coderVM viewBindings sid result bindings |
	coderVM := [ aContext requesterObject coderViewModel ]
		on: Error do: [ nil ].
	viewBindings := coderVM ifNotNil: [ coderVM viewPharoBindings ].
	sid := viewBindings
		ifNotNil: [ LeElixirSnippetElement sessionIdFor: viewBindings ].
	result := self bindAndExecute: aSourceString
		inContext: aContext
		sessionId: sid.
	self ensureSessionFinalizerFor: viewBindings
		sessionId: sid
		coderViewModel: coderVM.
	bindings := self fetchBindingsWithSessionId: sid.
	bindings associationsDo: [ :assoc |
		viewBindings ifNotNil: [
			(viewBindings bindingOf: assoc key asSymbol) value: assoc value ] ].
	^ result
]

{ #category : 'private' }
GtElixirCoderModel >> selfObjectFor: aContext [
	"I return the inspector selfObject from aContext's requester, or nil
	 if the snippet isn't in an inspector playground."
	| req |
	req := aContext requesterObject.
	^ (req notNil and: [ req respondsTo: #selfObject ])
		ifTrue: [ req selfObject ]
		ifFalse: [ nil ]
]

{ #category : 'private' }
GtElixirCoderModel >> wrapSource: sourceString withSelf: selfObj [
	"I prepend only the self binding; module context lives in the
	 session env (ensureSessionPrimed:sessionId:), so user code keeps
	 its own line numbers, one line off."
	(selfObj notNil and: [ selfObj respondsTo: #resolve ])
		ifFalse: [ ^ sourceString ].
	^ 'self = ' , selfObj resolve , String lf , sourceString
]
