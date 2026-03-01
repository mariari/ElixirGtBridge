Class {
	#name : 'GtElixirSnippetCoderViewModel',
	#superclass : 'GtSourceCoderViewModel',
	#instVars : [
		'selfObject',
		'viewPharoBindings'
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

{ #category : 'accessing' }
GtElixirSnippetCoderViewModel >> viewPharoBindings [
	^ viewPharoBindings
]

{ #category : 'accessing' }
GtElixirSnippetCoderViewModel >> viewPharoBindings: aBindings [
	viewPharoBindings := aBindings
]
