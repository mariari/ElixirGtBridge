Class {
	#name : 'GtElixirSnippetCoderViewModel',
	#superclass : 'GtSourceCoderViewModel',
	#instVars : [
		'selfObject',
		'viewPharoBindings',
		'sessionFinalizerRegistered'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'accessing' }
GtElixirSnippetCoderViewModel >> newCompletionStrategy [
	| strategy |
	strategy := GtElixirCompletionStrategy new
		coderModel: self coderModel;
		coderViewModel: self.
	viewPharoBindings ifNotNil: [ :bindings |
		strategy sessionId: (LeElixirSnippetElement sessionIdFor: bindings) ].
	^ strategy
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
GtElixirSnippetCoderViewModel >> sessionFinalizerRegistered [
	^ sessionFinalizerRegistered ifNil: [ false ]
]

{ #category : 'accessing' }
GtElixirSnippetCoderViewModel >> sessionFinalizerRegistered: aBoolean [
	sessionFinalizerRegistered := aBoolean
]

{ #category : 'accessing' }
GtElixirSnippetCoderViewModel >> viewPharoBindings [
	^ viewPharoBindings
]

{ #category : 'accessing' }
GtElixirSnippetCoderViewModel >> viewPharoBindings: aBindings [
	viewPharoBindings := aBindings
]
