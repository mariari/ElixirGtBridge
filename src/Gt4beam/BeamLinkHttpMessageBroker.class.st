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
