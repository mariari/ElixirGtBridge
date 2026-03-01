Class {
	#name : 'ElixirExecutionHandler',
	#superclass : 'LanguageLinkExecutionHandler',
	#category : 'Gt4beam-Global',
	#package : 'Gt4beam',
	#tag : 'Global'
}

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
