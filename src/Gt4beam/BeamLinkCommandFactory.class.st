Class {
	#name : 'BeamLinkCommandFactory',
	#superclass : 'LanguageLinkCommandFactory',
	#instVars : [
		'sessionId'
	],
	#category : 'Gt4beam-Execution',
	#package : 'Gt4beam',
	#tag : 'Execution'
}

{ #category : 'accessing' }
BeamLinkCommandFactory >> sessionId [
	^ sessionId
]

{ #category : 'accessing' }
BeamLinkCommandFactory >> sessionId: aString [
	sessionId := aString
]

{ #category : 'building' }
BeamLinkCommandFactory >> buildCommand [
	| cmd |
	cmd := super buildCommand.
	cmd sessionId: sessionId.
	^ cmd
]

{ #category : 'initalization' }
BeamLinkCommandFactory >> setNotifyToInstruction: anInstruction [
	| trimmedSource parsed last |
	anInstruction ifNil: [ ^ anInstruction ].
	trimmedSource := SmaCCString on: anInstruction trimRight.
	parsed := ElixirParser parse: trimmedSource.
	last := parsed expressions expressions last.
	trimmedSource insert: ', command_id, port)' at: last stopPosition + 1.
	trimmedSource insert: 'GtBridge.Eval.notify(' at: last startPosition.
	^ trimmedSource asString
]
