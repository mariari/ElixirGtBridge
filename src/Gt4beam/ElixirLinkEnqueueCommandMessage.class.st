Class {
	#name : 'ElixirLinkEnqueueCommandMessage',
	#superclass : 'LanguageLinkEnqueueCommandMessage',
	#instVars : [
		'sessionId'
	],
	#category : 'Gt4beam-Execution',
	#package : 'Gt4beam',
	#tag : 'Execution'
}

{ #category : 'accessing' }
ElixirLinkEnqueueCommandMessage >> sessionId [
	^ sessionId
]

{ #category : 'accessing' }
ElixirLinkEnqueueCommandMessage >> sessionId: aString [
	sessionId := aString
]

{ #category : 'encoding' }
ElixirLinkEnqueueCommandMessage >> privateEncode: dict [
	super privateEncode: dict.
	sessionId ifNotNil: [ dict at: #sessionId put: sessionId ]
]
