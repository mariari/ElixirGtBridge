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
		'application',
		'functionName',
		'arity'
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
BeamCompileFailureNotification >> arity: anIntegerOrNil [
	arity := anIntegerOrNil
]

{ #category : 'testing' }
BeamCompileFailureNotification >> canOpen [
	^ moduleName isNotNil
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
BeamCompileFailureNotification >> functionLineLabel [
	"Second-line content: function/arity (line N), or just (line N),
	 or empty when neither is known."
	| parts |
	parts := OrderedCollection new.
	self hasFunction ifTrue: [ parts add: functionName , '/' , arity asString ].
	self hasLine ifTrue: [ parts add: '(line ' , line asString , ')' ].
	^ ' ' join: parts
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> functionName: aStringOrNil [
	functionName := aStringOrNil
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> functionTarget [
	^ self hasFunction
		ifTrue: [ ElixirFunctionScrollTarget new
			functionName: functionName
			arity: arity ]
		ifFalse: [ nil ]
]

{ #category : 'testing' }
BeamCompileFailureNotification >> hasFunction [
	^ functionName isNotNil and: [ arity isNotNil ]
]

{ #category : 'testing' }
BeamCompileFailureNotification >> hasLine [
	^ line isNotNil and: [ line > 0 ]
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
BeamCompileFailureNotification >> resolveApplication [
	^ application ifNil: [ BeamLinkApplication uniqueInstance ]
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> shortMessage [
	"First non-blank line of the error, truncated to 100 chars."
	| msg firstLine |
	msg := errorMessage ifNil: [ ^ '(no message)' ].
	firstLine := (msg lines detect: [ :l | l trimBoth isNotEmpty ] ifNone: [ msg ]) trimBoth.
	^ firstLine size > 100
		ifTrue: [ (firstLine first: 100) , '…' ]
		ifFalse: [ firstLine ]
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> sourcePath [
	^ sourcePath
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> sourcePath: aStringOrNil [
	sourcePath := aStringOrNil
]

{ #category : 'accessing' }
BeamCompileFailureNotification >> title [
	^ 'Compile failed for ' , moduleName asString
]
