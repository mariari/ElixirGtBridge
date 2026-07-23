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
BeamLinkDeserializer >> charsFrom: aSentinelArray [
	"The pid, ref and port sentinels carry their printed form as
	 character codes after the tag."
	^ String withAll: (aSentinelArray allButFirst collect: [ :c | c asCharacter ])
]

{ #category : 'wire decoding' }
BeamLinkDeserializer >> decodeWire: aValue [
	"I turn `GtBridge.Serializer.to_json`'s wire form into GT values,
	 recursively.  I am the GT counterpart of `desanitize/1`, and I am
	 total over the format: every sentinel it emits has a case here.

	 A pid crosses as its printed form, which names the process exactly,
	 so I rebuild a live BeamPIDObject: it costs nothing, needs no
	 registry slot, and keeps every view the object carries.  Refs and
	 ports are equally reconstructible but have no proxy class, so they
	 stay as their printed text rather than a list of character codes."
	| decoded |
	aValue isArray ifTrue: [
		aValue isEmpty ifTrue: [ ^ aValue ].
		aValue first = '__atom__' ifTrue: [
			^ BeamAtomObject new: (aValue at: 2) asSymbol ].
		aValue first = '__base64__' ifTrue: [
			^ ZnBase64Encoder new decode: (aValue at: 2) ].
		aValue first = '__fun__' ifTrue: [ ^ aValue at: 2 ].
		aValue first = '__pid__' ifTrue: [
			^ BeamPIDObject new
				elixirVar: (self charsFrom: aValue);
				application: self application;
				yourself ].
		(#('__ref__' '__port__') includes: aValue first) ifTrue: [
			^ self charsFrom: aValue ].
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
	"The LanguageLink hook for turning a decoded response into GT
	 objects.  `decodeWire:` is that, and total over the wire format,
	 so there is one implementation rather than two that drift."
	^ self decodeWire: rawObj
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
