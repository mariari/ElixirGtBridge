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

{ #category : 'wire decoding' }
BeamLinkDeserializer >> decodeWire: aValue [
	"I turn `GtBridge.Serializer.to_json`'s wire form into GT values,
	 recursively.  Sentinel arrays become their objects, `__atom__:`
	 keys lose their prefix, and a map carrying exid reifies as a
	 proxy.

	 Tuples and pids arrive as values, so they become an Array and the
	 printed pid string.  Anything needing live identity must come
	 across as a proxy instead."
	| decoded |
	aValue isArray ifTrue: [
		aValue isEmpty ifTrue: [ ^ aValue ].
		aValue first = '__atom__' ifTrue: [
			^ BeamAtomObject new: (aValue at: 2) asSymbol ].
		aValue first = '__base64__' ifTrue: [
			^ ZnBase64Encoder new decode: (aValue at: 2) ].
		aValue first = '__pid__' ifTrue: [
			^ String withAll: (aValue allButFirst collect: [ :c | c asCharacter ]) ].
		aValue first = '__tuple__' ifTrue: [
			^ aValue allButFirst collect: [ :e | self decodeWire: e ] ].
		^ aValue collect: [ :e | self decodeWire: e ] ].
	aValue isDictionary ifFalse: [ ^ aValue ].
	decoded := Dictionary new: aValue size.
	aValue keysAndValuesDo: [ :k :v |
		decoded at: (self unprefixAtomKey: k) put: (self decodeWire: v) ].
	^ (decoded includesKey: 'exid')
		ifTrue: [ self reifyProxyFor: decoded ]
		ifFalse: [ decoded ]
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

{ #category : 'wire decoding' }
BeamLinkDeserializer >> unprefixAtomKey: aKey [
	"Serializer.to_json marks atom-valued map keys with an `__atom__:`
	 prefix.  I strip it so callers see the plain name."
	^ (aKey isString and: [ aKey beginsWith: '__atom__:' ])
		ifTrue: [ aKey allButFirst: 9 ]
		ifFalse: [ aKey ]
]
