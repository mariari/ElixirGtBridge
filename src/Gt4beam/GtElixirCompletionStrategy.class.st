Class {
	#name : 'GtElixirCompletionStrategy',
	#superclass : 'GtStreamedCompletionStrategy',
	#instVars : [
		'coderModel'
	],
	#category : 'Gt4beam-Completion',
	#package : 'Gt4beam',
	#tag : 'Completion'
}

{ #category : 'accessing' }
GtElixirCompletionStrategy >> coderModel [
	^ coderModel
]

{ #category : 'accessing' }
GtElixirCompletionStrategy >> coderModel: aCoderModel [
	coderModel := aCoderModel
]

{ #category : 'testing' }
GtElixirCompletionStrategy >> hasCompletionEntryFor: aString [
	^ aString size >= 2
]

{ #category : 'testing' }
GtElixirCompletionStrategy >> isSeparatorCharacter: aCharacter [
	^ aCharacter isSeparator
		or: [ '()[]{}.,;=+-*/<>|#' includes: aCharacter ]
]

{ #category : 'completion' }
GtElixirCompletionStrategy >> completionStringStreamStartingWith: aString [
	| results |
	results := [ self fetchCompletionsFor: aString ]
		on: Error
		do: [ :e | #() ].
	^ results asAsyncStream
]

{ #category : 'private' }
GtElixirCompletionStrategy >> fetchCompletionsFor: aString [
	| application serverAddress url response |
	coderModel ifNil: [ ^ #() ].
	application := coderModel initializeApplication.
	application ifNil: [ ^ #() ].
	serverAddress := application settings serverSocketAddress.
	url := 'http://' , serverAddress ipOrName , ':'
		, serverAddress port asString , '/COMPLETE'.
	response := ZnClient new
		url: url;
		entity: (ZnEntity
				with: (STONJSON toString: { 'code' -> aString } asDictionary)
				type: ZnMimeType applicationJson);
		post;
		response.
	response isSuccess ifFalse: [ ^ #() ].
	^ STONJSON fromString: response contents
]
