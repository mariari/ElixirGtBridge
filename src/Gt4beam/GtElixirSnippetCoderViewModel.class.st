Class {
	#name : 'GtElixirSnippetCoderViewModel',
	#superclass : 'GtSourceCoderViewModel',
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'accessing' }
GtElixirSnippetCoderViewModel >> newCompletionStrategy [
	^ GtElixirCompletionStrategy new
]
