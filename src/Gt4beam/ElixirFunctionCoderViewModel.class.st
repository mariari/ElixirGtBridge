Class {
	#name : 'ElixirFunctionCoderViewModel',
	#superclass : 'GtSourceCoderViewModel',
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'accessing' }
ElixirFunctionCoderViewModel >> elementClass [
	^ GtExpandableSourceCoderElement
]

{ #category : 'as yet unclassified' }
ElixirFunctionCoderViewModel >> newCompletionStrategy [
	| strategy |
	strategy := GtElixirCompletionStrategy new
		coderModel: self coderModel;
		coderViewModel: self.
	self coderModel moduleCoder ifNotNil: [ :mc |
		mc editorSessionId ifNotNil: [ :sid | strategy sessionId: sid ] ].
	^ strategy
]

{ #category : 'actions' }
ElixirFunctionCoderViewModel >> save [
	"I delegate to the coder model's single save method.
	 Called from Ctrl-S via requestSave."
	self coderModel saveFunction.
	^ true
]
