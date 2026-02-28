Class {
	#name : 'GtElixirSnippetCoderViewModel',
	#superclass : 'GtSourceCoderViewModel',
	#instVars : [
		'selfObject'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'accessing' }
GtElixirSnippetCoderViewModel >> newCompletionStrategy [
	^ GtElixirCompletionStrategy new
		coderModel: self coderModel;
		coderViewModel: self
]

{ #category : 'accessing' }
GtElixirSnippetCoderViewModel >> selfObject [
	^ selfObject
]

{ #category : 'accessing' }
GtElixirSnippetCoderViewModel >> selfObject: anObject [
	selfObject := anObject
]
