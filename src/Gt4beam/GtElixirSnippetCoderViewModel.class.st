Class {
	#name : 'GtElixirSnippetCoderViewModel',
	#superclass : 'GtSourceCoderViewModel',
	#instVars : [
		'sharedSnippetContext',
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
	"I read my page's receiver off the shared snippet context every
	 time rather than keeping a copy of it. The context is the one
	 place the receiver lives -- LePageViewModel>>receiver: writes it
	 -- so there is nothing here to keep in step with it."

	^ sharedSnippetContext ifNotNil: [ :aContext | aContext selfObject ]
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
GtElixirSnippetCoderViewModel >> sharedSnippetContext: aSharedSnippetContext [
	sharedSnippetContext := aSharedSnippetContext
]

{ #category : 'accessing' }
GtElixirSnippetCoderViewModel >> viewPharoBindings [
	^ viewPharoBindings
]

{ #category : 'accessing' }
GtElixirSnippetCoderViewModel >> viewPharoBindings: aBindings [
	viewPharoBindings := aBindings
]
