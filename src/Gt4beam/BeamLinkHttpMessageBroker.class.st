Class {
	#name : 'BeamLinkHttpMessageBroker',
	#superclass : 'LanguageLinkHttpMessageBroker',
	#category : 'Gt4beam-Pharo-MessageBroker',
	#package : 'Gt4beam',
	#tag : 'Pharo-MessageBroker'
}

{ #category : 'accessing' }
BeamLinkHttpMessageBroker class >> serializerClass [
	^ ElixirLinkNeoJsonSerializer
]

{ #category : 'private' }
BeamLinkHttpMessageBroker >> sendAsyncMessage: msg [
	"Upstream discards this answer, because it expects the result to
	 arrive later as a second HTTP request.  Ours rides back in the reply
	 body, so I hand it to the caller."
	^ self primSendMessage: msg encode
]
