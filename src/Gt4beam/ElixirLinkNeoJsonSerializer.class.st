Class {
	#name : 'ElixirLinkNeoJsonSerializer',
	#superclass : 'LanguageLinkNeoJsonSerializer',
	#category : 'Gt4beam-Pharo-MessageBroker',
	#package : 'Gt4beam',
	#tag : 'Pharo-MessageBroker'
}

{ #category : 'private' }
ElixirLinkNeoJsonSerializer >> deserialize: aString [
	| read |
	read := NeoJSONReader fromString: aString.
	
	"read
		at: 'value'
		ifPresent: [ read at: 'value' update: [ :val | self handleElixirSpecificData: val ] ] ifAbsent: []."
	^ self handleElixirSpecificData: read
]

{ #category : 'private' }
ElixirLinkNeoJsonSerializer >> handleElixirSpecificData: anObject [
	"kinda poor as I just check an array, rather than mapping over everthing
	
	Need to handle __pid__ as well"

	anObject isArray
		ifTrue: [ (anObject at: 1) = '__atom__'
				ifTrue: [ ^ BeamAtomObject new: (anObject at: 2) asSymbol ].
			(anObject at: 1) = '__base64__'
				ifTrue: [ ^ ZnBase64Encoder new decode: (anObject at: 2) ] ].
	^ anObject
]
