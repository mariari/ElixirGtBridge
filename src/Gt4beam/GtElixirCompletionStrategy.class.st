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
GtElixirCompletionStrategy >> completionActionStreamFor: aText at: positionInteger requested: aBoolean [
	| string first prefix results |
	string := aText asString.
	first := (string first: positionInteger)
		findLast: [ :c | self isSeparatorCharacter: c ].
	prefix := string copyFrom: first + 1 to: positionInteger.
	results := [ self fetchCompletionsFor: prefix ]
		on: Error do: [ #() ].
	^ results asAsyncStream
		collect: [ :each |
			| insertText |
			insertText := (each includes: $/)
				ifTrue: [ each copyUpTo: $/ ]
				ifFalse: [ each ].
			GtInsertTextCompletionAction
				labeled: (self labelFor: each withSearch: prefix)
				completion: (insertText allButFirst: prefix size)
				position: positionInteger
				from: positionInteger - prefix size + 1 ]
]

{ #category : 'testing' }
GtElixirCompletionStrategy >> hasCompletionsAt: anInteger in: aText [
	| char |
	(anInteger < 1 or: [ anInteger > aText size ]) ifTrue: [ ^ false ].
	char := aText at: anInteger.
	^ (self isCompletionCharacter: char)
		or: [ char = ${ and: [ self opensStructAt: anInteger in: aText ] ]
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
	coderViewModel sourceText ifNotNil: [ :src |
		| srcString sepIdx |
		srcString := src asString.
		"sourceText may lag one keystroke; rebuild tail from aString.
		 Find the last separator before cursor and append aString."
		sepIdx := srcString findLast: [ :c | self isSeparatorCharacter: c ].
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

{ #category : 'private' }
GtElixirCompletionStrategy >> labelFor: aString withSearch: searchString [
	| text |
	text := aString asRopedText glamorousCodeFont.
	(text from: 1 to: searchString size)
		attributes: { BlTextDecorationAttribute new
			color: BrGlamorousColors textHighlightColor;
			thickness: 3;
			underline }.
	^ text
]

{ #category : 'testing' }
GtElixirCompletionStrategy >> isCompletionCharacter: aCharacter [
	^ aCharacter isLetter
		or: [ aCharacter isDigit or: [ aCharacter = $_ or: [ aCharacter = $. ] ] ]
]

{ #category : 'testing' }
GtElixirCompletionStrategy >> opensStructAt: anInteger in: aText [
	| index |
	index := anInteger - 1.
	[ index >= 1 and: [ self isCompletionCharacter: (aText at: index) ] ]
		whileTrue: [ index := index - 1 ].
	^ index >= 1 and: [ (aText at: index) = $% ]
]

{ #category : 'testing' }
GtElixirCompletionStrategy >> isSeparatorCharacter: aCharacter [
	^ aCharacter isSeparator
		or: [ '()[]{},;=+-*/<>|#' includes: aCharacter ]
]
