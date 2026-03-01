Class {
	#name : 'GtElixirCompletionStrategy',
	#superclass : 'GtStreamedCompletionStrategy',
	#instVars : [
		'coderModel',
		'coderViewModel'
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

{ #category : 'accessing' }
GtElixirCompletionStrategy >> coderViewModel [
	^ coderViewModel
]

{ #category : 'accessing' }
GtElixirCompletionStrategy >> coderViewModel: aCoderViewModel [
	coderViewModel := aCoderViewModel
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
	| application serverAddress url response payload |
	coderModel ifNil: [ ^ #() ].
	application := coderModel initializeApplication.
	application ifNil: [ ^ #() ].
	serverAddress := application settings serverSocketAddress.
	url := 'http://' , serverAddress ipOrName , ':'
		, serverAddress port asString , '/COMPLETE'.
	payload := { 'code' -> aString } asDictionary.
	coderModel sessionId ifNotNil: [ :sid |
		payload at: #sessionId put: sid ].
	coderViewModel sourceText ifNotNil: [ :src |
		| srcString sepIdx |
		srcString := src asString.
		"sourceText may lag one keystroke; rebuild tail from aString.
		 Find the last separator before cursor and append aString."
		sepIdx := srcString size.
		[ sepIdx > 0 and: [ (self isSeparatorCharacter: (srcString at: sepIdx)) not ] ]
			whileTrue: [ sepIdx := sepIdx - 1 ].
		payload at: 'source' put: (srcString first: sepIdx) , aString ].
	response := ZnClient new
		url: url;
		entity: (ZnEntity
				with: (STONJSON toString: payload)
				type: ZnMimeType applicationJson);
		post;
		response.
	response isSuccess ifFalse: [ ^ #() ].
	^ STONJSON fromString: response contents
]

{ #category : 'testing' }
GtElixirCompletionStrategy >> hasCompletionEntryFor: aString [
	^ aString size >= 2
]

{ #category : 'testing' }
GtElixirCompletionStrategy >> isSeparatorCharacter: aCharacter [
	^ aCharacter isSeparator
		or: [ '()[]{},;=+-*/<>|#' includes: aCharacter ]
]
