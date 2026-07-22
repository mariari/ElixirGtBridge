Class {
	#name : 'BeamSessionFinalizer',
	#superclass : 'Object',
	#instVars : [
		'sessionId',
		'application'
	],
	#category : 'Gt4beam-Global',
	#package : 'Gt4beam',
	#tag : 'Global'
}

{ #category : 'instance creation' }
BeamSessionFinalizer class >> sessionId: aString application: anApplication [
	^ self new
		sessionId: aString;
		application: anApplication
]

{ #category : 'accessing' }
BeamSessionFinalizer >> application: anApplication [
	application := anApplication
]

{ #category : 'finalization' }
BeamSessionFinalizer >> finalize [
	"Session close is fire-and-forget over the framed transport: no
	 answer, so no promise -- just hand the request to the broker."
	([ application isRunning ] on: Error do: [ ^ self ]) ifFalse: [ ^ self ].
	[ application settings messageBroker primSendMessage: (Dictionary new
		at: 'type' put: 'SESSION_CLOSE';
		at: 'sessionId' put: sessionId;
		yourself) ]
		on: Error do: [ "broker may be down" ]
]

{ #category : 'accessing' }
BeamSessionFinalizer >> sessionId: aString [
	sessionId := aString
]
