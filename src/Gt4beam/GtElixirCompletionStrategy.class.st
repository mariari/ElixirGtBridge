Class {
	#name : 'GtElixirCompletionStrategy',
	#superclass : 'GtStreamedCompletionStrategy',
	#instVars : [
		'coderModel',
		'coderViewModel',
		'sessionId',
		'sessionImportsLoaded'
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

{ #category : 'private' }
GtElixirCompletionStrategy >> ensureSessionImports [
	"I preload module imports into the eval session. Fallback for
	 cases where the snippet element didn't preload (e.g. no self
	 object at element creation time)."
	sessionImportsLoaded == true ifTrue: [ ^ self ].
	[ | selfObj modName sid |
		selfObj := (coderViewModel respondsTo: #selfObject)
			ifTrue: [ coderViewModel selfObject ]
			ifFalse: [ nil ].
		selfObj ifNil: [ ^ self ].
		modName := (selfObj respondsTo: #elixirClass)
			ifTrue: [ selfObj elixirClass ]
			ifFalse: [ nil ].
		modName ifNil: [ ^ self ].
		sid := sessionId ifNil: [ 'default' ].
		BeamLinkApplication uniqueInstance evaluateAndWait:
			'GtBridge.Eval.Preamble.editor_session(' , modName , ', "' , sid , '")'.
		sessionImportsLoaded := true ]
		on: Error do: [ "retry next time" ]
]

{ #category : 'private' }
GtElixirCompletionStrategy >> fetchCompletionsFor: aString [
	"Completion goes over the framed transport as a COMPLETE request the
	 reader resolves by id; the result is the completion list itself.

	 I read the application via #application -- both GtElixirCoderModel
	 (snippets, lazy-inits) and ElixirFunctionCoder (delegates to
	 moduleCoder, already running) implement it."
	| application payload |
	coderModel ifNil: [ ^ #() ].
	self ensureSessionImports.
	application := coderModel application.
	application ifNil: [ ^ #() ].
	payload := Dictionary new.
	payload at: 'type' put: 'COMPLETE'.
	payload at: 'code' put: aString.
	self sessionId ifNotNil: [ :sid | payload at: 'sessionId' put: sid ].
	coderViewModel sourceText ifNotNil: [ :src |
		| srcString sepIdx |
		srcString := src asString.
		sepIdx := srcString findLast: [ :c | self isSeparatorCharacter: c ].
		payload at: 'source' put: (srcString first: sepIdx) , aString ].
	^ [ application executionHandler requestAndWait: payload ]
		on: Error do: [ #() ]
]

{ #category : 'testing' }
GtElixirCompletionStrategy >> hasCompletionEntryFor: aString [
	^ aString size >= 2
]

{ #category : 'testing' }
GtElixirCompletionStrategy >> hasCompletionsAt: anInteger in: aText [
	^ true
]

{ #category : 'testing' }
GtElixirCompletionStrategy >> isSeparatorCharacter: aCharacter [
	^ aCharacter isSeparator
		or: [ '()[]{},;=+-*/<>|#' includes: aCharacter ]
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

{ #category : 'accessing' }
GtElixirCompletionStrategy >> sessionId [
	^ sessionId ifNil: [
		coderViewModel ifNotNil: [ :vm |
			vm viewPharoBindings ifNotNil: [ :bindings |
				LeElixirSnippetElement sessionIdFor: bindings ] ] ]
]

{ #category : 'accessing' }
GtElixirCompletionStrategy >> sessionId: aString [
	sessionId := aString
]
