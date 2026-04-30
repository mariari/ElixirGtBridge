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
	"I splice the current editor text back into the module source at
	 my function's line range, save and recompile. Called from Ctrl-S
	 via GtSourceCoderSaveShortcut → requestSave → save.
	 currentSourceString lives on the coder model (GtSourceCoder), not
	 on the view model — route through coderModel."
	| coder |
	coder := self coderModel.
	coder moduleCoder
		spliceFunction: coder currentSourceString
		fromLine: coder startLine
		toLine: coder endLine.
	^ true
]
