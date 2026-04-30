Class {
	#name : 'ElixirFunctionCoder',
	#superclass : 'GtSourceCoder',
	#traits : 'TElixirNavigationCoder',
	#classTraits : 'TElixirNavigationCoder classTrait',
	#instVars : [
		'moduleCoder',
		'functionName',
		'arity',
		'startLine',
		'endLine',
		'selfObject',
		'showsModuleInHeader',
		'kind',
		'indent'
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
	 GT's method coder delete pattern. Skipped for macro-generated
	 functions (no source = nothing to splice out)."
	self hasSource ifFalse: [ ^ self ].
	anAddOns
		addDropDownWithPreviewAction: 'Remove' translated
		icon: BrGlamorousVectorIcons bin
		action: [ :aButtonElement :aButtonModel :anEvent |
			moduleCoder
				spliceFunction: ''
				forFunction: functionName
				arity: arity ]
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
	"Skipped for macro-generated functions (no source line means
	 there's no slot in the file to swap with a neighbor)."
	self hasSource ifFalse: [ ^ self ].
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
		icon: BrGlamorousVectorIcons play
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
	"Skipped for macro-generated functions — saving requires a
	 source location to splice into."
	self hasSource ifFalse: [ ^ self ].
	anAddOns
		addMainAction: 'Save' translated
		icon: BrGlamorousVectorIcons accept
		action: [ :aCoderVM :anElement | self saveFunction ]
		id: #elixirFunctionSaveAction
]

{ #category : 'accessing' }
ElixirFunctionCoder >> application [

	"I return the BEAM application via my module coder."

	^ moduleCoder application
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
	"Tint the '(no source)' suffix via background, not foreground:
	 element-level `foreground:` clobbers per-char foreground."
	| text |
	(self isType or: [ startLine isNotNil and: [ startLine > 0 ] ])
		ifTrue: [ ^ self signature asRopedText ].
	text := (self signature, ' (no source)') asRopedText.
	text
		attribute: (BlTextBackgroundAttribute paint: (Color fromHexString: 'FFE0E6'))
		from: self signature size + 1 to: text size.
	^ text
]

{ #category : 'private' }
ElixirFunctionCoder >> computeAst: theSourceString [
	^ ElixirParser parseWithErrors: theSourceString
]

{ #category : 'navigation' }
ElixirFunctionCoder >> contextModuleName [
	^ moduleCoder moduleName
]

{ #category : 'private' }
ElixirFunctionCoder >> dedentSource: aString [
	"I record the common leading-space indent of aString on `indent`
	 and return aString with that prefix stripped from each line.
	 Functions inside a defmodule arrive indented; `Code.format_string!`
	 normalises top-level expressions to column 0, so without this
	 the buffer-vs-baseline diff is permanent and Ctrl-Shift-F would
	 always look modified.  `reindent:` puts the prefix back on save."
	| lines minIndent |
	lines := aString lines.
	minIndent := SmallInteger maxVal.
	lines do: [ :line |
		line trimRight isEmpty ifFalse: [
			| leading |
			leading := 0.
			[ leading < line size and: [ (line at: leading + 1) = Character space ] ]
				whileTrue: [ leading := leading + 1 ].
			minIndent := minIndent min: leading ] ].
	minIndent = SmallInteger maxVal ifTrue: [ minIndent := 0 ].
	indent := String new: minIndent withAll: Character space.
	minIndent = 0 ifTrue: [ ^ aString ].
	^ String streamContents: [ :s |
		| first |
		first := true.
		lines do: [ :line |
			first ifTrue: [ first := false ] ifFalse: [ s nextPut: Character lf ].
			s nextPutAll: (line size >= minIndent
				ifTrue: [ line copyFrom: minIndent + 1 to: line size ]
				ifFalse: [ line trimLeft ]) ] ]
]

{ #category : 'accessing' }
ElixirFunctionCoder >> functionName [
	^ functionName
]

{ #category : 'testing' }
ElixirFunctionCoder >> hasSource [
	"I am false for macro-generated functions (the analysis emits
	 entries with start = 0 for runtime exports without an AST).
	 Save/Delete/Move actions are nonsensical for such entries.
	 Type entries with a real source location (typedstruct block,
	 @type declaration) flow through the same line-range splice
	 path as functions — Save/Move work for them too."
	^ startLine isNotNil and: [ startLine > 0 ]
]

{ #category : 'as yet unclassified' }
ElixirFunctionCoder >> initializeAddOns: addOns [
	super initializeAddOns: addOns.
	addOns
		addStyler: (GtCoderAstSmaCCParserStyler new smaccStyler: ElixirParser gtStyler).
	addOns
		addStyler: ElixirFunctionExpanderStyler new
]

{ #category : 'as yet unclassified' }
ElixirFunctionCoder >> initializeAddOns: addOns viewModel: aViewModel [
	"Populate the action bar imperatively in display order. Save
	 leftmost matches `GtPharoMethodCoder`; Discard is contributed
	 separately via `<gtAstCoderAddOns: 2>` and only when modified."
	super initializeAddOns: addOns viewModel: aViewModel.
	#(addSaveAddOnsTo:to:from:
	  addRunAddOnsTo:to:from:
	  addHelpAddOnsTo:to:from:
	  addMoveAddOnsTo:to:from:
	  addDeleteAddOnsTo:to:from:)
		do: [ :sel |
			self perform: sel with: addOns with: aViewModel with: self ]
]

{ #category : 'initialization' }
ElixirFunctionCoder >> initializeFromEntry: anEntry moduleCoder: anElixirModuleCoder [
	moduleCoder := anElixirModuleCoder.
	self refreshFromEntry: anEntry
]

{ #category : 'as yet unclassified' }
ElixirFunctionCoder >> initializeShortcuts: addOns [
	super initializeShortcuts: addOns.
	addOns addShortcut: GtSourceCoderSaveShortcut new.
	addOns addShortcut: ElixirCoderFormatShortcut new.
	self initializeNavigationShortcuts: addOns
]

{ #category : 'accessing' }
ElixirFunctionCoder >> isType [
	"I am true for entries that came from Code.Typespec.fetch_types/1
	 (rendered as typedstruct blocks or @type bodies)."
	^ kind == #type or: [ kind == #opaque or: [ kind == #typep ] ]
]

{ #category : 'accessing' }
ElixirFunctionCoder >> kind [
	^ kind
]

{ #category : 'add-ons' }
ElixirFunctionCoder >> modifiedAddOnsFor: anAst into: coderAddOns [
	<gtAstCoderAddOns: 2>
	"I add the ✗ Discard main action only when there are pending
	 edits — mirrors `GtPharoMethodCoder >> modifiedMessageAstFor:
	 into:`. The framework re-runs me whenever the coder's modified
	 state changes, so the action appears on first edit and
	 disappears on save."
	self hasSource ifFalse: [ ^ self ].
	self isModified ifFalse: [ ^ self ].
	coderAddOns
		addMainAction: 'Discard changes' translated
		icon: BrGlamorousVectorIcons cancel
		action: [ :aCoderUIModel :anElement | aCoderUIModel discardChanges ]
		id: #elixirFunctionDiscardAction
]

{ #category : 'accessing' }
ElixirFunctionCoder >> moduleCoder [
	^ moduleCoder
]

{ #category : 'as yet unclassified' }
ElixirFunctionCoder >> moveBy: anOffset [
	"Filter out macro-generated entries (start = 0) before indexing:
	 they have no file location and can't be spliced."
	| entries myIndex targetIndex |
	entries := (moduleCoder functionEntries
		select: [ :e | (e attributeAt: #start) > 0 ])
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

{ #category : 'initialization' }
ElixirFunctionCoder >> refreshFromEntry: anEntry [
	"Bridge hands `#kind` back as either BeamAtomObject or ByteString
	 depending on the serializer path; normalise to a symbol."
	| rawKind |
	functionName := (anEntry attributeAt: #name) asString.
	arity := anEntry attributeAt: #arity.
	startLine := anEntry attributeAt: #start.
	endLine := anEntry attributeAt: #end_line.
	rawKind := anEntry attributeAt: #kind.
	kind := (rawKind respondsTo: #symbol)
		ifTrue: [ rawKind symbol ]
		ifFalse: [ rawKind asString asSymbol ].
	self sourceCode: (GtCoderExplicitStringSource new source: (self dedentSource: (anEntry attributeAt: #source) asString))
]

{ #category : 'as yet unclassified' }
ElixirFunctionCoder >> refreshLinesAfterSwap [
	"After a swap, my startLine/endLine in the file may have changed.
	 I re-find my entry by name+arity+source contents match."
	| entries mySource myEntry |
	mySource := self currentSourceText asString trimmed.
	entries := moduleCoder functionEntries.
	myEntry := entries detect: [ :e |
		(e attributeAt: #name) asString = functionName
			and: [ (e attributeAt: #arity) = arity
			and: [ ((e attributeAt: #source) asString trimmed) = mySource ] ] ]
		ifNone: [ nil ].
	myEntry ifNotNil: [
		startLine := myEntry attributeAt: #start.
		endLine := myEntry attributeAt: #end_line ]
]

{ #category : 'private' }
ElixirFunctionCoder >> reindent: aString [
	"I re-prepend the indent recorded by `dedentSource:` to each
	 non-blank line so the spliced text aligns with the surrounding
	 module body."
	(indent isNil or: [ indent isEmpty ]) ifTrue: [ ^ aString ].
	^ String streamContents: [ :s |
		| first |
		first := true.
		aString lines do: [ :line |
			first ifTrue: [ first := false ] ifFalse: [ s nextPut: Character lf ].
			line trimRight isEmpty ifFalse: [ s nextPutAll: indent ].
			s nextPutAll: line ] ]
]

{ #category : 'actions' }
ElixirFunctionCoder >> saveFunction [
	"I splice my current source text into the module file at
	 my function's position (found by name/arity) and recompile.
	 Then reset my source to the formatted result from the freshly
	 cached entries — saveAndCompile fires BeamModuleRecompiled
	 which primes moduleCoder.functionEntries, so no second bridge
	 round-trip is needed."
	| match freshSource |
	moduleCoder
		spliceFunction: (self reindent: self currentSourceString)
		forFunction: functionName
		arity: arity.
	match := moduleCoder functionEntries
		detect: [ :e | (e attributeAt: #name) asString = functionName
			and: [ (e attributeAt: #arity) = arity ] ]
		ifNone: [ ^ self ].
	freshSource := (match attributeAt: #source) asString.
	self sourceCode: (GtCoderExplicitStringSource new source: (self dedentSource: freshSource))
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
ElixirFunctionCoder >> showsModuleInHeader [
	"I control whether the row's headerElementClass is the clickable
	 Module > function/arity breadcrumb (filter results) or nil
	 (Functions tab — module is implicit, no need to repeat per row)."
	^ showsModuleInHeader == true
]

{ #category : 'accessing' }
ElixirFunctionCoder >> showsModuleInHeader: aBoolean [
	showsModuleInHeader := aBoolean
]

{ #category : 'accessing' }
ElixirFunctionCoder >> signature [
	^ functionName, '/', arity asString
]

{ #category : 'accessing' }
ElixirFunctionCoder >> startLine [
	^ startLine
]
