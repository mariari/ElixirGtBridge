Class {
	#name : 'ElixirFunctionScrollTarget',
	#superclass : 'GtStreamingCodersViewModelScrollTarget',
	#instVars : [
		'startLine',
		'functionName',
		'arity'
	],
	#category : 'Gt4beam',
	#package : 'Gt4beam'
}

{ #category : 'testing' }
ElixirFunctionScrollTarget >> applicableTo: aCoderViewModel [
	"I prefer name+arity matching when set — that's the only way to
	 land on macro-generated entries (which all have startLine = 0,
	 so a startLine match would land on the first one alphabetically).
	 Fall back to startLine when only that's set."
	| coder |
	coder := aCoderViewModel coder.
	functionName isNotNil
		ifTrue: [
			^ (coder respondsTo: #functionName)
				and: [ coder functionName = functionName
				and: [ arity isNil or: [ coder arity = arity ] ] ] ].
	startLine isNotNil
		ifTrue: [
			^ (coder respondsTo: #startLine)
				and: [ coder startLine = startLine ] ].
	^ false
]

{ #category : 'accessing' }
ElixirFunctionScrollTarget >> functionName: aName arity: anArity [
	functionName := aName.
	arity := anArity
]

{ #category : 'printing' }
ElixirFunctionScrollTarget >> printTargetNameOn: aStream [
	functionName isNotNil
		ifTrue: [ aStream nextPutAll: functionName; nextPut: $/; print: (arity ifNil: [ '?' ]) ]
		ifFalse: [ aStream nextPutAll: 'function at line '; print: startLine ]
]

{ #category : 'accessing' }
ElixirFunctionScrollTarget >> startLine: aLineNumber [
	startLine := aLineNumber
]
