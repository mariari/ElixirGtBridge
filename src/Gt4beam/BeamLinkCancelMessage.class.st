Class {
	#name : 'BeamLinkCancelMessage',
	#superclass : 'LanguageLinkAsyncMessage',
	#instVars : [
		'commandId',
		'sessionId'
	],
	#category : 'Gt4beam-Execution',
	#package : 'Gt4beam',
	#tag : 'Execution'
}

{ #category : 'accessing' }
BeamLinkCancelMessage class >> type [
	^ #CANCEL
]

{ #category : 'accessing' }
BeamLinkCancelMessage >> commandId: aString [
	commandId := aString
]

{ #category : 'encoding' }
BeamLinkCancelMessage >> privateEncode: dict [
	dict at: #commandId put: commandId.
	sessionId ifNotNil: [ dict at: #sessionId put: sessionId ]
]

{ #category : 'accessing' }
BeamLinkCancelMessage >> sessionId: aString [
	sessionId := aString
]
