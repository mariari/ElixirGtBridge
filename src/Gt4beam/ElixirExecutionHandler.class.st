Class {
	#name : 'ElixirExecutionHandler',
	#superclass : 'LanguageLinkExecutionHandler',
	#category : 'Gt4beam-Global',
	#package : 'Gt4beam',
	#tag : 'Global'
}

{ #category : 'messaging' }
ElixirExecutionHandler >> buildMessageFromCommand: command [
	| message |
	message := ElixirLinkEnqueueCommandMessage
		commandId: command id
		statements: command codeForRemote
		bindings: (command bindings collect: [ :obj | self serialize: obj ]).
	message addBinding: #pharoCommandId -> (self serialize: command id).
	message sessionId: command sessionId.
	^ message
]

{ #category : 'as yet unclassified' }
ElixirExecutionHandler >> cancelCommand: command [
	"I tell the node to stop the eval this command started. Without me
	 a stopped snippet keeps running there and every later request for
	 its session queues behind it."
	self communicationHandler sendMessage: (BeamLinkCancelMessage new
		commandId: command id;
		sessionId: command sessionId;
		yourself)
]

{ #category : 'initialization' }
ElixirExecutionHandler >> initializeHandler [
	commandQueue := LanguageLinkCommandRegistry executionHandler: self.
	mapperFactory := LanguageLinkMapperFactory forExecutionHandler: self.
	promiseRegistry := LanguageLinkPromiseRegistry new.
	weakRegistry := self settings platform weakRegistry.
	objectRegistry := LanguageLinkObjectRegistry new.

	self communicationHandler
		addHandler: [ :msg | self notifyHandler: msg ]
			forMessageClass: LanguageLinkUpdatePromiseMessage;
		addHandler: [ :msg | self notifyErrorHandler: msg ]
			forMessageClass: LanguageLinkErrorMessage;
		addHandler: [ :msg | self notifyCallbackHandler: msg ]
			forMessageClass: LanguageLinkCallbackMessage
]

{ #category : 'private' }
ElixirExecutionHandler >> primitiveSendCommand: command [
	"The result rides back in the ENQUEUE reply rather than arriving as a
	 second HTTP request, so I resolve the promise from the reply here.
	 `sendCommand:` registers the promise before calling me."
	| response |
	response := super primitiveSendCommand: command.
	(response isDictionary and: [ response includesKey: 'value' ]) ifTrue: [
		self
			updatePromiseId: command id
			with: ([ self deserialize: (response at: 'value') ]
				on: Error do: [ :ex | ex ]) ].
	^ response
]

{ #category : 'as yet unclassified' }
ElixirExecutionHandler >> registerObject: aProxyObject [
	"Don't register the object. Gets a new proxy every time"
	weakRegistry 
		registerObject: aProxyObject 
		finalizer: (LanguageLinkRegistryFinalizer 
							variable: aProxyObject elixirVar
							executionHandler: self)
]

{ #category : 'as yet unclassified' }
ElixirExecutionHandler >> removeId: aRemoteProxyId [
	^ 'GtBridge.Eval.remove(' , aRemoteProxyId asString , ')'
]

{ #category : 'requesting' }
ElixirExecutionHandler >> requestAndWait: aDict [
	"Send a typed request over the transport and block on the promise the
	 reader resolves by commandId.  Completion and bindings need an answer
	 but are not evals, so they bypass the command factory; I still
	 register a command and a promise so the reader's resolution path
	 (finishCommandId: then signal) finds both."
	| id command promise |
	id := UUID new asString36.
	aDict at: 'commandId' put: id.
	command := ElixirLinkCommand new.
	command instVarNamed: 'id' put: id.
	commandQueue addCommand: command.
	promise := LanguageLinkPromise new id: id; yourself.
	promiseRegistry addPromise: promise.
	self application settings messageBroker primSendMessage: aDict.
	promise wait.
	^ promise value
]
