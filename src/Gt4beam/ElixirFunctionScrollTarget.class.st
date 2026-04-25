Class {
	#name : 'ElixirFunctionScrollTarget',
	#superclass : 'GtStreamingCodersViewModelScrollTarget',
	#instVars : [
		'startLine'
	],
	#category : 'Gt4beam',
	#package : 'Gt4beam'
}

{ #category : 'testing' }
ElixirFunctionScrollTarget >> applicableTo: aCoderViewModel [
	"I match function coder VMs by start line."
	^ (aCoderViewModel coder respondsTo: #startLine)
		and: [ aCoderViewModel coder startLine = startLine ]
]

{ #category : 'printing' }
ElixirFunctionScrollTarget >> printTargetNameOn: aStream [
	aStream nextPutAll: 'function at line '; print: startLine
]

{ #category : 'accessing' }
ElixirFunctionScrollTarget >> startLine: aLineNumber [
	startLine := aLineNumber
]
