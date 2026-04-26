Class {
	#name : 'ElixirModuleCoder',
	#superclass : 'GtCoderModel',
	#traits : 'TGtCoderTrait',
	#classTraits : 'TGtCoderTrait classTrait',
	#instVars : [
		'sourcePath',
		'moduleName',
		'application',
		'focusLine',
		'focusFunctionTarget',
		'sessionId',
		'selfObject',
		'saving'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'instance creation' }
ElixirModuleCoder class >> forModule: aModuleName application: anApp [
	"I fetch the module's source file path via the BEAM bridge.
	 The case expression guarantees the result is either a binary
	 or nil — without it, compile_source's to_string return value
	 has sometimes come back across the bridge as a BeamProxyObject
	 wrapping the raw Erlang charlist, which then DNU'd when the
	 Smalltalk side tried to use it as a String path."
	| path |
	path := [ anApp evaluateAndWait:
		'case GtBridge.Resolve.source_file(', aModuleName, ') do
		 nil -> nil
		 s when is_binary(s) -> s
		 s when is_list(s) -> List.to_string(s)
		 _ -> nil
		 end' ]
		on: Error do: [ nil ].
	^ self new
		moduleName: aModuleName;
		application: anApp;
		sourcePath: ((path isKindOf: String) ifTrue: [ path ] ifFalse: [ nil ]);
		yourself
]

{ #category : 'actions' }
ElixirModuleCoder >> addFunction: newText [
	"I insert newText just before the module's closing `end`, so new
	 functions land after any types, attributes, and existing defs.
	 findLast: is critical — a backward loop without early termination
	 would fall through every `end` and land on the earliest one (a
	 nested def's close), splicing the new function inside that def."
	| lines lastEnd newLines |
	lines := self sourceCode lines asOrderedCollection.
	lastEnd := lines findLast: [ :line | line trimBoth = 'end' ].
	lastEnd = 0 ifTrue: [ lastEnd := lines size + 1 ].
	newLines := (lines copyFrom: 1 to: lastEnd - 1) asOrderedCollection.
	newLines add: ''.
	newLines addAll: newText lines.
	newLines addAll: (lines copyFrom: lastEnd to: lines size).
	^ self saveAndCompile: (String lf join: newLines)
]

{ #category : 'as yet unclassified' }
ElixirModuleCoder >> announceFunctionsChanged [
	"I announce that my functions have changed, so the streaming list refreshes."
	self announce: (GtCoderSourceCodeChanged new coder: self)
]

{ #category : 'as yet unclassified' }
ElixirModuleCoder >> announceSourceChangedAcrossInstances [
	"I tell every other live ElixirModuleCoder pointing at the same
	 module to refresh.  Saves can come from a transient coder created
	 by an inline |> expander; without this broadcast, the long-lived
	 coder feeding the user's Coder tab keeps showing stale source
	 because it never hears the per-instance announcement."
	self announceFunctionsChanged.
	self class allInstances do: [ :each |
		(each ~~ self and: [ each moduleName = moduleName ])
			ifTrue: [ each announceFunctionsChanged ] ]
]

{ #category : 'accessing' }
ElixirModuleCoder >> application [
	^ application
]

{ #category : 'accessing' }
ElixirModuleCoder >> application: anApp [
	application := anApp
]

{ #category : 'accessing' }
ElixirModuleCoder >> asCoderViewModel [
	^ ElixirModuleCoderViewModel new coder: self
]

{ #category : 'private' }
ElixirModuleCoder >> buildExampleMapElement [
	"I build a Mondrian graph of example dependencies."
	| mondrian data edges nodes app modName |
	app := self application.
	modName := self moduleName.
	data := (app evaluateAndWait:
		'GtBridge.Analysis.example_deps(', modName, ')') asList.
	edges := OrderedCollection new.
	data do: [ :pair |
		| from tos |
		from := pair itemAt: 0.
		tos := (pair itemAt: 1) asList.
		tos do: [ :to | edges add: from -> to ] ].
	nodes := data collect: [ :pair | pair itemAt: 0 ].
	mondrian := GtMondrian new.
	mondrian nodes
		stencil: [ :name |
			BeamMondrianHelpers
				nodeLabeled: name
				color: (Color fromHexString: '#e6f5ec')
				onClick: [ :evt |
					evt target phlow spawnObject:
						(app newCommandFactory << (modName, '.', name, '()'); sendAndWait) ] ];
		with: nodes.
	mondrian edges stencil: [ BeamMondrianHelpers edgeStencil ];
		connectToAll: [ :name |
			(edges select: [ :e | e key = name ]) collect: #value ].
	mondrian layout horizontalDominanceTree.
	^ mondrian root
]

{ #category : 'private' }
ElixirModuleCoder >> buildFunctionsViewElement [
	"I build the Functions tab. If focusLine is set, I set a scroll
	 target on the view model — the streaming element handles
	 scroll via list scrollToItemSuchThat:offset: when the matching
	 item loads (same pattern as GtPharoStreamingMethodsCoderElement).
	 Each function coder starts folded so the user scans the list."
	| container addRow streaming vm streamingElement focusStart |
	container := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical matchParent ].
	addRow := BrHorizontalPane new
		hMatchParent;
		vFitContent;
		padding: (BlInsets top: 3 left: 6 bottom: 3 right: 6);
		addChild: (BrButton new
			aptitude: BrGlamorousButtonWithIconAptitude;
			icon: BrGlamorousVectorIcons add;
			beSmallSize;
			label: 'Add function';
			action: [ :btn | self buildAddFunctionDraftPaneIn: container afterRow: addRow ]);
		yourself.
	streaming := ElixirFunctionStreamingModel forModuleCoder: self.
	vm := ElixirFoldedCodersViewModel new
		streamingCodersModel: streaming;
		yourself.
	streamingElement := ElixirFunctionStreamingElement new
		streamingCodersViewModel: vm;
		yourself.
	"Caller-supplied focusFunctionTarget wins (works for macro-generated
	 entries with no source line, and for source-having entries when
	 the caller knows the function name).  Otherwise build a startLine
	 target from focusLine."
	focusFunctionTarget
		ifNotNil: [ vm scrollToTarget: focusFunctionTarget ]
		ifNil: [
			focusStart := focusLine ifNotNil: [ :lines |
				lines isArray ifTrue: [ lines first ] ifFalse: [ lines ] ].
			focusStart ifNotNil: [
				vm scrollToTarget: (ElixirFunctionScrollTarget new startLine: focusStart) ] ].
	container
		addChild: addRow;
		addChild: streamingElement matchParent.
	^ container
]

{ #category : 'private' }
ElixirModuleCoder >> buildAddFunctionDraftPaneIn: container afterRow: addRow [
	"I insert a draft editor pane immediately after addRow. The draft
	 uses my editor session so completion sees my imports/aliases.
	 Save splices the draft via addFunction: and removes the pane;
	 the source-change announcement refreshes the streaming list.
	 Cancel just removes the pane."
	| vm editor draftPane header existing |
	existing := container children detect: [ :c | c == addRow ] ifNone: [ nil ].
	existing ifNil: [ ^ self ].
	"Bail if a draft is already open — addRow is always at index 1 and
	 if there's a draft it sits at index 2; we don't want two drafts."
	container children size > 2 ifTrue: [ ^ self ].
	vm := self coderModelForSource:
		'def new_function do', String lf, '  :ok', String lf, 'end'.
	vm
		when: GtSourceCoderViewModelSaveRequested
		do: [ :ann |
			self addFunction: vm coderModel currentSourceString.
			draftPane removeFromParent.
			ann consumed: true ].
	editor := vm asElement matchParent.
	header := BrHorizontalPane new
		hMatchParent;
		vFitContent;
		alignCenterLeft;
		padding: (BlInsets top: 3 left: 6 bottom: 3 right: 6);
		addChild: (BrLabel new
			aptitude: (BrGlamorousLabelAptitude new glamorousCodeFont; fontSize: 12);
			text: 'New function');
		addChild: (BrFrame new hMatchParent vFitContent);
		addChild: (BrButton new
			aptitude: BrGlamorousButtonWithIconAptitude;
			icon: BrGlamorousVectorIcons accept;
			beSmallSize;
			label: 'Add & compile';
			action: [ :btn |
				self addFunction: vm coderModel currentSourceString.
				draftPane removeFromParent ]);
		addChild: (BrButton new
			aptitude: BrGlamorousButtonWithIconAptitude;
			icon: BrGlamorousVectorIcons cancel;
			beSmallSize;
			label: 'Cancel';
			action: [ :btn | draftPane removeFromParent ]);
		yourself.
	draftPane := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical exact: 220 ];
		padding: (BlInsets all: 4);
		border: (BlBorder paint: (Color gray alpha: 0.4) width: 1);
		addChild: header;
		addChild: editor;
		yourself.
	container addChild: draftPane at: 2
]

{ #category : 'private' }
ElixirModuleCoder >> coderModelForSource: sourceText [
	"I return a GtElixirCoderModel view model wired to my editor
	 session so completion sees my imports/aliases."
	| coderModel vm |
	coderModel := GtElixirCoderModel new.
	coderModel elixirLinkApplicationStrategy: LeElixirApplicationStrategy new.
	coderModel sourceCode: (GtCoderExplicitStringSource new source: sourceText).
	vm := coderModel asCoderViewModel.
	vm expanded: true.
	self editorSessionId ifNotNil: [ :sid |
		| bindings |
		bindings := GtSharedVariablesBindings new.
		vm viewPharoBindings: bindings.
		LeElixirSnippetElement sessionMap at: bindings put: sid ].
	^ vm
]

{ #category : 'private' }
ElixirModuleCoder >> buildSourceViewElement [
	"I build a self-refreshing container for the Source tab. The inner
	 coder is rebuilt whenever GtCoderSourceCodeChanged fires on me.
	 If focusLine is set, I scroll to that line after rendering."
	| container rebuild |
	container := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical matchParent ].
	rebuild := [
		| coderModel vm element |
		container removeChildren.
		coderModel := GtElixirCoderModel new.
		coderModel elixirLinkApplicationStrategy: LeElixirApplicationStrategy new.
		coderModel contextModuleName: moduleName.
		coderModel sourceCode: (GtCoderExplicitStringSource new source: self sourceCode).
		vm := coderModel asCoderViewModel.
		vm expanded: true.
		vm
			when: GtSourceCoderViewModelSaveRequested
			do: [ :ann |
				self saveAndCompile: coderModel currentSourceString.
				ann consumed: true ].
		focusLine ifNotNil: [ :lines |
			| startLine source pos |
			startLine := lines isArray
				ifTrue: [ lines first ]
				ifFalse: [ lines ].
			source := self sourceCode.
			pos := 0.
			1 to: (startLine - 1 min: source lines size) do: [ :i |
				pos := pos + (source lines at: i) size + 1 ].
			vm moveCursorTo: pos.
			vm scrollToLine: startLine withCharacterPosition: 1 ].
		container addChild: vm asElement matchParent ].
	rebuild value.
	self announcer
		when: GtCoderSourceCodeChanged
		do: [ :ann | rebuild value ].
	^ container
]

{ #category : 'accessing' }
ElixirModuleCoder >> coderName [
	^ moduleName
]

{ #category : 'accessing' }
ElixirModuleCoder >> editorSessionId [
	"I return a unique session ID for this coder instance, with the
	 module's imports/aliases/requires loaded. The session is finalized
	 when this coder is GC'd."
	^ sessionId ifNil: [
		sessionId := 'editor_', moduleName, '_', UUID new asString.
		application evaluateAndWait:
			'GtBridge.Analysis.editor_session(', moduleName, ', "', sessionId, '")'.
		FinalizationRegistry default
			add: self
			finalizer: (BeamSessionFinalizer sessionId: sessionId application: application).
		sessionId ]
]

{ #category : 'accessing' }
ElixirModuleCoder >> focusLine [
	^ focusLine
]

{ #category : 'accessing' }
ElixirModuleCoder >> focusLine: aLineNumber [
	focusLine := aLineNumber
]

{ #category : 'accessing' }
ElixirModuleCoder >> focusFunctionTarget: aTarget [
	"I take an ElixirFunctionScrollTarget directly so callers that
	 know the function name+arity (BeamDocumentationObject>>gtCoderFor:)
	 can land on macro-generated entries that share startLine = 0."
	focusFunctionTarget := aTarget
]

{ #category : 'accessing' }
ElixirModuleCoder >> functionEntries [
	"I return all function entries with line ranges, annotations, and source text."
	^ [ application evaluateAndWait:
		'GtBridge.Analysis.all_functions(', moduleName, ')' ]
		on: Error do: [ #() ]
]

{ #category : 'as yet unclassified' }
ElixirModuleCoder >> gtDependenciesViewFor: aView context: aContext [
	<gtElixirModuleView>
	^ aView forward
		title: 'Dependencies';
		priority: 40;
		object: [ self application evaluateAndWait:
			'GtBridge.Documentation.for_module(', self moduleName, ')' ];
		view: #gtDependenciesFor:
]

{ #category : 'gt-extensions' }
ElixirModuleCoder >> gtExamplesViewFor: aView context: aContext [
	<gtElixirModuleView>
	| hasExamples |
	hasExamples := [ self application evaluateAndWait:
		'function_exported?(', self moduleName, ', :__examples__, 0)' ]
		on: Error do: [ false ].
	hasExamples ifFalse: [ ^ aView empty ].
	^ aView explicit
		title: 'Examples';
		priority: 30;
		stencil: [ self buildExampleMapElement ]
]

{ #category : 'gt-extensions' }
ElixirModuleCoder >> gtFunctionsViewFor: aView context: aContext [
	<gtElixirModuleView>
	self hasFunctions ifFalse: [ ^ aView empty ].
	^ aView explicit
		title: 'Functions';
		priority: 9;
		stencil: [ self buildFunctionsViewElement ]
]

{ #category : 'as yet unclassified' }
ElixirModuleCoder >> gtHelpViewFor: aView context: aContext [
	<gtElixirModuleView>
	^ aView forward
		title: 'Help';
		priority: 25;
		object: [ self application evaluateAndWait:
			'GtBridge.Documentation.for_module(', self moduleName, ')' ];
		view: #gtRemoteViewsFor:
]

{ #category : 'gt-extensions' }
ElixirModuleCoder >> gtSourceViewFor: aView context: aContext [
	<gtElixirModuleView>
	self hasLocalSource ifFalse: [ ^ aView empty ].
	^ aView explicit
		title: 'Source';
		priority: 20;
		stencil: [ self buildSourceViewElement ]
]

{ #category : 'as yet unclassified' }
ElixirModuleCoder >> hasFunctions [
	"I return true if the bridge can enumerate my functions.
	 Precompiled modules without debug info return empty."
	^ [ (self functionEntries asList) isNotEmpty ]
		on: Error do: [ false ]
]

{ #category : 'as yet unclassified' }
ElixirModuleCoder >> hasLocalSource [
	"I return true if my sourcePath is a String pointing to an
	 existing file on this machine. Guarding on isKindOf: String
	 so a stray BeamProxyObject (from a bridge quirk we've seen on
	 some modules) degrades to 'no local source' instead of
	 crashing on #asFileReference."
	(sourcePath isKindOf: String) ifFalse: [ ^ false ].
	^ sourcePath asFileReference exists
]

{ #category : 'accessing' }
ElixirModuleCoder >> moduleName [
	^ moduleName
]

{ #category : 'accessing' }
ElixirModuleCoder >> moduleName: aString [
	moduleName := aString
]

{ #category : 'actions' }
ElixirModuleCoder >> saveAndCompile: newSource [
	"I write source to disk, format, recompile, and announce the source
	 change so views listening to me refresh (Source tab, function stream).
	 Preserves the original file's line ending convention and trailing
	 newline."
	| b64 normalized usesCrlf ending result |
	usesCrlf := self sourceCode includesSubstring: String crlf.
	ending := usesCrlf ifTrue: [ String crlf ] ifFalse: [ String lf ].
	normalized := newSource copyReplaceAll: String crlf with: String lf.
	normalized := normalized copyReplaceAll: String cr with: String lf.
	usesCrlf ifTrue: [
		normalized := normalized copyReplaceAll: String lf with: String crlf ].
	(normalized endsWith: ending) ifFalse: [
		normalized := normalized , ending ].
	b64 := ZnBase64Encoder new encode: normalized utf8Encoded.
	result := application newCommandFactory
		<< ('GtBridge.Analysis.hot_reload("', sourcePath, '", Base.decode64!("', b64, '"))');
		sendAndWait.
	self announceSourceChangedAcrossInstances.
	^ result
]

{ #category : 'accessing' }
ElixirModuleCoder >> sourceCode [
	^ sourcePath asFileReference contents
]

{ #category : 'accessing' }
ElixirModuleCoder >> selfObject [
	^ selfObject
]

{ #category : 'accessing' }
ElixirModuleCoder >> selfObject: anObject [
	selfObject := anObject
]

{ #category : 'accessing' }
ElixirModuleCoder >> sourcePath [
	^ sourcePath
]

{ #category : 'accessing' }
ElixirModuleCoder >> sourcePath: aString [
	sourcePath := aString
]

{ #category : 'actions' }
ElixirModuleCoder >> spliceFunction: newText forFunction: aName arity: anArity [
	"I find the function's current position in the file by name/arity,
	 splice the new text in, and save. Skips if a save is already running."
	| entries match lines newLines st en |
	saving == true ifTrue: [ ^ self ].
	saving := true.
	[ entries := [ (application evaluateAndWait:
		'GtBridge.Analysis.all_functions(', moduleName, ')') asList ]
		on: Error do: [ #() ].
	match := entries
		detect: [ :e | (e attributeAt: #name) asString = aName
			and: [ (e attributeAt: #arity) = anArity ] ]
		ifNone: [ ^ self ].
	st := match attributeAt: #start.
	en := match attributeAt: #end_line.
	lines := self sourceCode lines.
	newLines := (lines copyFrom: 1 to: st - 1) asOrderedCollection.
	newLines addAll: newText lines.
	newLines addAll: (lines copyFrom: en + 1 to: lines size).
	self saveAndCompile: (String lf join: newLines) ]
	ensure: [ saving := false ]
]

{ #category : 'actions' }
ElixirModuleCoder >> swapFunctions: entryA with: entryB [
	"I swap two function blocks in the source, save, and compile."
	| lines startA endA startB endB blockA blockB newLines t |
	startA := entryA attributeAt: #start.
	endA := entryA attributeAt: #end_line.
	startB := entryB attributeAt: #start.
	endB := entryB attributeAt: #end_line.
	"Ensure A comes before B"
	startA > startB ifTrue: [
		t := startA. startA := startB. startB := t.
		t := endA. endA := endB. endB := t ].
	lines := self sourceCode lines.
	blockA := lines copyFrom: startA to: endA.
	blockB := lines copyFrom: startB to: endB.
	newLines := (lines copyFrom: 1 to: startA - 1),
		blockB,
		(lines copyFrom: endA + 1 to: startB - 1),
		blockA,
		(lines copyFrom: endB + 1 to: lines size).
	^ self saveAndCompile: (String lf join: newLines)
]
