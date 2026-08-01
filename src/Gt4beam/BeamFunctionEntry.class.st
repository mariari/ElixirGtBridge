"
I wrap a function-entry Dictionary from the SSE stream so it answers
the `attributeAt:` protocol used by `BeamProxyObject`.
"
Class {
	#name : 'BeamFunctionEntry',
	#superclass : 'Object',
	#instVars : [
		'fields'
	],
	#category : 'Gt4beam-Analysis',
	#package : 'Gt4beam',
	#tag : 'Analysis'
}

{ #category : 'instance creation' }
BeamFunctionEntry class >> fields: aDictionary [
	^ self new fields: aDictionary; yourself
]

{ #category : 'accessing' }
BeamFunctionEntry >> attributeAt: aKey [
	^ fields at: aKey asString ifAbsent: [ nil ]
]

{ #category : 'accessing' }
BeamFunctionEntry >> fields: aDictionary [
	fields := aDictionary
]
