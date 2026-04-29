Class {
	#name : 'BeamInspectorMode',
	#superclass : 'Object',
	#instVars : [
		'name',
		'priority',
		'tool',
		'object'
	],
	#category : 'Gt4beam-Inspector',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'instance creation' }
BeamInspectorMode class >> empty [
	^ self new
]

{ #category : 'testing' }
BeamInspectorMode >> isEmpty [
	^ tool isNil
]

{ #category : 'accessing' }
BeamInspectorMode >> name [
	^ name
]

{ #category : 'accessing' }
BeamInspectorMode >> name: aString [
	name := aString
]

{ #category : 'accessing' }
BeamInspectorMode >> object [
	^ object
]

{ #category : 'accessing' }
BeamInspectorMode >> object: anObject [
	object := anObject
]

{ #category : 'accessing' }
BeamInspectorMode >> priority [
	^ priority ifNil: [ 50 ]
]

{ #category : 'accessing' }
BeamInspectorMode >> priority: aNumber [
	priority := aNumber
]

{ #category : 'accessing' }
BeamInspectorMode >> tool [
	^ tool
]

{ #category : 'accessing' }
BeamInspectorMode >> tool: aTool [
	tool := aTool
]
