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

{ #category : 'as yet unclassified' }
BeamLinkCommandFactory >> sendAndWait [
	"I cancel my command on the node if my caller is terminated while
	 waiting. Stopping a snippet unwinds the waiting process, and
	 ifCurtailed: is where that becomes a message rather than silence.
	 A cancel that cannot be sent is not worth failing the unwind for."
	| command |
	command := self buildCommand.
	^ self performSendWithLogging: [
		[ (self application send: command) waitForValue ]
			ifCurtailed: [
				[ self application executionHandler cancelCommand: command ]
					on: Error do: [ :anError | nil ] ] ]
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
