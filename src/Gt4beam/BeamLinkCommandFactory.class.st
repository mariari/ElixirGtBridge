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

{ #category : 'building' }
BeamLinkCommandFactory >> buildCommand [
	| cmd |
	cmd := super buildCommand.
	cmd sessionId: sessionId.
	^ cmd
]

{ #category : 'accessing' }
BeamLinkCommandFactory >> sessionId [
	^ sessionId
]

{ #category : 'accessing' }
BeamLinkCommandFactory >> sessionId: aString [
	sessionId := aString
]

{ #category : 'initalization' }
BeamLinkCommandFactory >> setNotifyToInstruction: anInstruction [
	"I deliberately do not wrap.  Upstream wraps the last expression in a
	 notify call because it expects the result to arrive as a second HTTP
	 request; ours rides back in the ENQUEUE reply instead.  Finding the
	 expression to wrap cost a full SmaCC parse of every instruction."
	^ anInstruction
]
