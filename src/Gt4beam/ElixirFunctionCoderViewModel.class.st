Class {
	#name : 'ElixirFunctionCoderViewModel',
	#superclass : 'GtSourceCoderViewModel',
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'accessing' }
ElixirFunctionCoderViewModel >> elementClass [
	"I use ElixirFunctionCoderRowElement so the row can paint
	 its sidebar based on the coder's hasSource state."
	^ ElixirFunctionCoderRowElement
]

{ #category : 'accessing' }
ElixirFunctionCoderViewModel >> headerElementClass [
	"I show the clickable Module > function/arity breadcrumb only
	 for filter results — Functions-tab callers leave the coder's
	 showsModuleInHeader flag false so the module isn't repeated
	 per row.  GtSourceCoderContentElement>>onTextualCoderViewModelChanged
	 mounts the returned class as the first child of the collapsed
	 and expanded content elements when this is non-nil."
	^ self coder showsModuleInHeader
		ifTrue: [ ElixirFunctionCoderHeaderElement ]
		ifFalse: [ nil ]
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
