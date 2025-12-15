Class {
	#name : 'BeamLinkDeserializer',
	#superclass : 'LanguageLinkDeserializer',
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'as yet unclassified' }
BeamLinkDeserializer class >> deserialize: anObject [
	^ self new deserialize: anObject
]

{ #category : 'as yet unclassified' }
BeamLinkDeserializer >> buildProxyFor: rawObject [
	| proxy |
	proxy := (BeamProxyObject elixirClass: (rawObject at: #exclass))
			elixirVar: (rawObject at: #exid);
			rawData: rawObject;
			application: self application.
	self executionHandler registerObject: proxy.
	^ proxy
]

{ #category : 'as yet unclassified' }
BeamLinkDeserializer >> privateDeserialize: rawObj [

	rawObj isCollection ifFalse: [ ^ rawObj ].
	rawObj isDictionary
		and: [ (rawObj includesKey: #exid) ifTrue: [ ^ self reifyProxyFor: rawObj ] ].
	^ rawObj collect: [ :elem | self privateDeserialize: elem ]
]

{ #category : 'as yet unclassified' }
BeamLinkDeserializer >> reifyProxyFor: rawObj [
	^ self objectRegistry
		resolve: (rawObj at: #exid)
		ifAbsent: [ self buildProxyFor: rawObj ]
]
