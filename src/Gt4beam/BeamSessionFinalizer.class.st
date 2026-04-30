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
	| serverAddress url |
	([ application isRunning ] on: Error do: [ ^ self ])
		ifFalse: [ ^ self ].
	serverAddress := application settings serverSocketAddress.
	url := 'http://' , serverAddress ipOrName , ':'
		, serverAddress port asString , '/SESSION_CLOSE'.
	[ ZnClient new
		url: url;
		entity: (ZnEntity
			with: (STONJSON toString: { #sessionId -> sessionId } asDictionary)
			type: ZnMimeType applicationJson);
		post ]
		on: Error do: [ "server may be stopped" ]
]

{ #category : 'accessing' }
BeamSessionFinalizer >> sessionId: aString [
	sessionId := aString
]
