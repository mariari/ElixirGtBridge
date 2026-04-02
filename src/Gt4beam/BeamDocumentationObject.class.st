Class {
	#name : 'BeamDocumentationObject',
	#superclass : 'BeamProxyObject',
	#category : 'Gt4beam-Documentation',
	#package : 'Gt4beam',
	#tag : 'Documentation'
}

{ #category : 'accessing' }
BeamDocumentationObject class >> elixirClass [
	^ 'GtBridge.Documentation'
]

{ #category : 'accessing' }
BeamDocumentationObject >> functionLines [
	"I return {startLine. endLine} for a function-scoped Documentation, or nil."
	| result |
	result := self
		evaluateAndWait:
			'GtBridge.Resolve.function_lines(' , self resolve , ')'.
	result ifNil: [ ^ nil ].
	^ { result itemAt: 0. result itemAt: 1 }
]
