Class {
	#name : 'ElixirFunctionCoder',
	#superclass : 'GtSourceCoder',
	#instVars : [
		'moduleCoder',
		'functionName',
		'arity',
		'startLine',
		'endLine',
		'selfObject'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'instance creation' }
ElixirFunctionCoder class >> forEntry: anEntry moduleCoder: anElixirModuleCoder [
	^ self new initializeFromEntry: anEntry moduleCoder: anElixirModuleCoder
]

{ #category : 'add-ons' }
ElixirFunctionCoder >> addDeleteAddOnsTo: anAddOns to: aViewModel from: aCoderModel [
	<gtCoderAction>
	"I remove this function with a confirmation dropdown, matching
	 GT's method coder delete pattern."
	anAddOns
		addDropDownWithPreviewAction: 'Remove' translated
		icon: BrGlamorousVectorIcons bin
		action: [ :aButtonElement :aButtonModel :anEvent |
			moduleCoder
				spliceFunction: ''
				fromLine: startLine
				toLine: endLine ]
		stencil: [ :anElement |
			BrLabel new
				aptitude: BrGlamorousLabelAptitude new;
				text: 'Remove ', self signature;
				margin: (BlInsets all: 10) ]
		id: #elixirFunctionRemoveAction
]

{ #category : 'add-ons' }
ElixirFunctionCoder >> addHelpAddOnsTo: anAddOns to: aViewModel from: aCoderModel [
	<gtCoderAction>
	anAddOns
		addMainAction: 'Help' translated
		icon: BrGlamorousVectorIcons help
		action: [ :aCoderVM :anElement |
			anElement phlow spawnObject:
				(moduleCoder application evaluateAndWait:
					'GtBridge.Documentation.for_function(',
						moduleCoder moduleName, ', :', functionName, ', ', arity asString, ')') ]
		id: #elixirFunctionHelpAction
]

{ #category : 'add-ons' }
ElixirFunctionCoder >> addMoveAddOnsTo: anAddOns to: aViewModel from: aCoderModel [
	<gtCoderAction>
	anAddOns
		addMainAction: 'Move up' translated
		icon: BrGlamorousVectorIcons up
		action: [ :aCoderVM :anElement | self moveUp ]
		id: #elixirFunctionMoveUpAction.
	anAddOns
		addMainAction: 'Move down' translated
		icon: BrGlamorousVectorIcons down
		action: [ :aCoderVM :anElement | self moveDown ]
		id: #elixirFunctionMoveDownAction
]

{ #category : 'add-ons' }
ElixirFunctionCoder >> addRunAddOnsTo: anAddOns to: aViewModel from: aCoderModel [
	<gtCoderAction>
	"I run 0-arity functions directly, or 1-arity functions with
	 selfObject piped in as the first argument."
	| canRun callExpr |
	arity = 0 ifTrue: [
		callExpr := moduleCoder moduleName, '.', functionName, '()'.
		canRun := true ].
	(arity = 1 and: [ selfObject notNil ]) ifTrue: [
		callExpr := moduleCoder moduleName, '.', functionName, '(', selfObject resolve, ')'.
		canRun := true ].
	(canRun ifNil: [ false ]) ifFalse: [ ^ self ].
	anAddOns
		addMainAction: 'Run' translated
		icon: BrGlamorousVectorIcons playinspect
		action: [ :aCoderVM :anElement |
			anElement phlow spawnObject:
				(moduleCoder application newCommandFactory
					<< callExpr;
					sendAndWait) ]
		id: #elixirFunctionRunAction
]

{ #category : 'add-ons' }
ElixirFunctionCoder >> addSaveAddOnsTo: anAddOns to: aViewModel from: aCoderModel [
	<gtCoderAction>
	anAddOns
		addMainAction: 'Save' translated
		icon: BrGlamorousVectorIcons accept
		action: [ :aCoderVM :anElement |
			anElement phlow spawnObject: (moduleCoder
				spliceFunction: aCoderVM coderModel currentSourceString
				fromLine: startLine
				toLine: endLine) ]
		id: #elixirFunctionSaveAction
]

{ #category : 'accessing' }
ElixirFunctionCoder >> arity [
	^ arity
]

{ #category : 'converting' }
ElixirFunctionCoder >> asCoderViewModel [
	^ ElixirFunctionCoderViewModel new coder: self
]

{ #category : 'accessing' }
ElixirFunctionCoder >> collapsedText [
	^ self signature asRopedText
]

{ #category : 'private' }
ElixirFunctionCoder >> computeAst: theSourceString [
	^ ElixirParser parseWithErrors: theSourceString
]

{ #category : 'accessing' }
ElixirFunctionCoder >> endLine [
	^ endLine
]

{ #category : 'accessing' }
ElixirFunctionCoder >> functionName [
	^ functionName
]

{ #category : 'as yet unclassified' }
ElixirFunctionCoder >> initializeAddOns: addOns [
	super initializeAddOns: addOns.
	addOns
		addStyler: (GtCoderAstSmaCCParserStyler new smaccStyler: ElixirParser gtStyler)
]

{ #category : 'add-ons' }
ElixirFunctionCoder >> initializeAddOns: addOns viewModel: aViewModel [
	super initializeAddOns: addOns viewModel: aViewModel.
	self addSaveAddOnsTo: addOns to: aViewModel from: self.
	self addDeleteAddOnsTo: addOns to: aViewModel from: self.
	self addMoveAddOnsTo: addOns to: aViewModel from: self.
	self addRunAddOnsTo: addOns to: aViewModel from: self.
	self addHelpAddOnsTo: addOns to: aViewModel from: self
]

{ #category : 'as yet unclassified' }
ElixirFunctionCoder >> initializeApplication [
	"I return the running BEAM application via my module coder."
	| app |
	app := moduleCoder application.
	app ifNil: [ ^ nil ].
	app isRunning ifFalse: [ app start ].
	^ app
]

{ #category : 'as yet unclassified' }
ElixirFunctionCoder >> initializeShortcuts: addOns [
	"I add Ctrl-S save so editing a function and hitting save splices
	 it back into the module. GtSourceCoderSaveShortcut calls
	 requestSave on the view model which calls save, overridden on
	 ElixirFunctionCoderViewModel."
	super initializeShortcuts: addOns.
	addOns addShortcut: GtSourceCoderSaveShortcut new
]

{ #category : 'initialization' }
ElixirFunctionCoder >> initializeFromEntry: anEntry moduleCoder: anElixirModuleCoder [
	moduleCoder := anElixirModuleCoder.
	functionName := (anEntry attributeAt: #name) asString.
	arity := anEntry attributeAt: #arity.
	startLine := anEntry attributeAt: #start.
	endLine := anEntry attributeAt: #end_line.
	self sourceCode: (GtCoderExplicitStringSource new source: (anEntry attributeAt: #source) asString)
]

{ #category : 'accessing' }
ElixirFunctionCoder >> moduleCoder [
	^ moduleCoder
]

{ #category : 'as yet unclassified' }
ElixirFunctionCoder >> moveBy: anOffset [
	"I swap myself with my neighbor at myIndex + anOffset.
	 swapFunctions:with: calls saveAndCompile: which announces the
	 source change — no explicit announceFunctionsChanged needed."
	| entries myIndex targetIndex |
	entries := moduleCoder functionEntries asList
		sort: [ :a :b | (a attributeAt: #start) < (b attributeAt: #start) ].
	myIndex := entries detectIndex: [ :e | (e attributeAt: #start) = startLine ] ifNone: [ ^ self ].
	targetIndex := myIndex + anOffset.
	(targetIndex between: 1 and: entries size) ifFalse: [ ^ self ].
	moduleCoder swapFunctions: (entries at: myIndex) with: (entries at: targetIndex).
	self refreshLinesAfterSwap
]

{ #category : 'actions' }
ElixirFunctionCoder >> moveDown [
	self moveBy: 1
]

{ #category : 'actions' }
ElixirFunctionCoder >> moveUp [
	self moveBy: -1
]

{ #category : 'evaluation' }
ElixirFunctionCoder >> primitiveDebug: aSourceString inContext: aContext onFailDo: anEvaluationFailBlock [
	^ self primitiveEvaluate: aSourceString inContext: aContext onFailDo: anEvaluationFailBlock
]

{ #category : 'evaluation' }
ElixirFunctionCoder >> primitiveEvaluate: aSourceString inContext: aContext onFailDo: anEvaluationFailBlock [
	| app result sessionId |
	app := moduleCoder application.
	app ifNil: [ ^ anEvaluationFailBlock value ].
	sessionId := moduleCoder editorSessionId.
	[ result := sessionId
		ifNil: [ app evaluateAndWait: aSourceString ]
		ifNotNil: [ app newCommandFactory
			<< aSourceString;
			addBinding: 'session_id' -> sessionId;
			sendAndWait ] ]
		on: Error
		do: [ :ex | ^ anEvaluationFailBlock value ].
	^ result
]

{ #category : 'printing' }
ElixirFunctionCoder >> printOn: aStream [
	aStream nextPutAll: 'ElixirFunctionCoder('; nextPutAll: self signature; nextPut: $)
]

{ #category : 'as yet unclassified' }
ElixirFunctionCoder >> refreshLinesAfterSwap [
	"After a swap, my startLine/endLine in the file may have changed.
	 I re-find my entry by name+arity+source contents match."
	| entries mySource myEntry |
	mySource := self currentSourceText asString trimmed.
	entries := moduleCoder functionEntries asList.
	myEntry := entries detect: [ :e |
		(e attributeAt: #name) asString = functionName
			and: [ (e attributeAt: #arity) = arity
			and: [ ((e attributeAt: #source) asString trimmed) = mySource ] ] ]
		ifNone: [ nil ].
	myEntry ifNotNil: [
		startLine := myEntry attributeAt: #start.
		endLine := myEntry attributeAt: #end_line ]
]

{ #category : 'accessing' }
ElixirFunctionCoder >> selector [
	^ functionName asSymbol
]

{ #category : 'as yet unclassified' }
ElixirFunctionCoder >> selfObject [ ^ selfObject
]

{ #category : 'as yet unclassified' }
ElixirFunctionCoder >> selfObject: anObject [ selfObject := anObject
]

{ #category : 'accessing' }
ElixirFunctionCoder >> signature [
	^ functionName, '/', arity asString
]

{ #category : 'accessing' }
ElixirFunctionCoder >> startLine [
	^ startLine
]
