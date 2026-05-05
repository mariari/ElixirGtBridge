"
I notify the user that an Elixir module failed to compile, with an
Open button that spawns the offending module's coder focused on the
failing line.
"
Class {
	#name : 'BeamCompileFailureNotification',
	#superclass : 'GtNotificationEvent',
	#instVars : [
		'moduleName',
		'sourcePath',
		'line',
		'errorMessage',
		'application'
	],
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}

{ #category : 'accessing' }
BeamCompileFailureNotification >> application [
	^ application
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> application: anApp [
	application := anApp
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> elementClass [
	^ BeamCompileFailureNotificationElement
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> errorMessage [
	^ errorMessage
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> errorMessage: aString [
	errorMessage := aString
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> line [
	^ line
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> line: anIntegerOrNil [
	line := anIntegerOrNil
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> moduleName [
	^ moduleName
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> moduleName: aString [
	moduleName := aString
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> sourcePath [
	^ sourcePath
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> sourcePath: aStringOrNil [
	sourcePath := aStringOrNil
]

{ #category : 'testing' }
BeamCompileFailureNotification >> canOpen [
	^ moduleName isNotNil
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> resolveApplication [
	^ application ifNil: [ BeamLinkApplication uniqueInstance ]
]

{ #category : 'testing' }
BeamCompileFailureNotification >> hasLine [
	^ line isNotNil and: [ line > 0 ]
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> header [
	| base |
	base := 'Compile failed for ', moduleName asString.
	^ self hasLine
		ifTrue: [ base , ' (line ' , line asString , ')' ]
		ifFalse: [ base ]
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> summary [
	^ self header , ': ' , (errorMessage ifNil: [ '(no message)' ])
]
