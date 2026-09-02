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
		'saving',
		'sourceCache',
		'functionStreamingModel',
		'interfaceFlags',
		'relatedCoders',
		'cachedImports',
		'cachedImportsGeneration'
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

{ #category : 'namespace' }
ElixirModuleCoder class >> namespaceAncestorsOf: aString [
	"Name prefixes of a dotted module name, nearest first."
	| parts |
	parts := aString substrings: '.'.
	^ (parts size - 1 to: 1 by: -1) collect: [ :n |
		(parts first: n) inject: '' into: [ :acc :each |
			acc isEmpty ifTrue: [ each ] ifFalse: [ acc , '.' , each ] ] ]
]

{ #category : 'actions' }
ElixirModuleCoder >> addFunction: newText [
	"Append newText as a new function just before moduleName's closing
	 `end`, located from the parse so a sibling or nested module in the
	 same file doesn't misdirect it."
	^ self applySourceEdit:
		('GtBridge.Analysis.append_function(', (self base64Expr: self sourceCode),
			', "', self moduleName, '", ', (self base64Expr: newText), ')')
]

{ #category : 'accessing' }
ElixirModuleCoder >> application [
	^ application
]

{ #category : 'accessing' }
ElixirModuleCoder >> application: anApp [
	application := anApp
]

{ #category : 'private' }
ElixirModuleCoder >> applySourceEdit: anExpression [
	"Run an Analysis source-edit expression returning the new module source
	 and save it; skip the save on a bridge error (non-String result)."
	| result |
	result := application newCommandFactory << anExpression; sendAndWait.
	^ result isString ifTrue: [ self saveAndCompile: result ] ifFalse: [ self ]
]

{ #category : 'accessing' }
ElixirModuleCoder >> asCoderViewModel [
	^ ElixirModuleCoderViewModel new coder: self
]

{ #category : 'private' }
ElixirModuleCoder >> base64Expr: aString [
	"An Elixir Base.decode64! expression carrying aString, safe to embed as
	 a string argument in a bridge call."
	^ 'Base.decode64!("', (ZnBase64Encoder new encode: aString utf8Encoded), '")'
]

{ #category : 'private' }
ElixirModuleCoder >> buildAddFunctionDraftPaneIn: container afterRow: addRow [
	"I insert a draft editor pane immediately after addRow, seeded with a
	 new-function template.  It's an ElixirFunctionCoder (no eval buttons,
	 dedent), so its own Save appends via addFunction:; completion sees my
	 imports/aliases through my editor session.  The pane removes itself
	 once the append recompiles (the same GtCoderSourceCodeChanged the
	 streaming list refreshes on).  Cancel just removes the pane."
	| coder vm editor draftPane header existing |
	existing := container children detect: [ :c | c == addRow ] ifNone: [ nil ].
	existing ifNil: [ ^ self ].
	"Bail if a draft is already open — addRow is always at index 1 and
	 if there's a draft it sits at index 2; we don't want two drafts."
	container children size > 2 ifTrue: [ ^ self ].
	coder := ElixirFunctionCoder forNewFunctionIn: self.
	vm := coder asCoderViewModel.
	vm expanded: true.
	editor := vm asElement matchParent.
	header := BrHorizontalPane new
		hMatchParent;
		vFitContent;
		alignCenterLeft;
		padding: (BlInsets top: 3 left: 6 bottom: 3 right: 6);
		addChild: (BrLabel new
			aptitude: (BrGlamorousLabelAptitude new glamorousCodeFont; fontSize: 12);
			text: 'New function in');
		addChild: (self newTargetButtonFor: coder);
		addChild: (BrFrame new hMatchParent vFitContent);
		addChild: (BrButton new
			aptitude: BrGlamorousButtonWithIconAptitude;
			icon: BrGlamorousVectorIcons cancel;
			beSmallSize;
			label: 'Cancel';
			action: [ :btn |
				draftPane removeFromParent.
				self writableRangeCoders do: [ :each | each announcer unsubscribe: draftPane ] ]);
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
	"Whichever range module the draft is saved into recompiles; any of them
	 closing the pane is right, since the draft was appended somewhere."
	self writableRangeCoders do: [ :target |
		target announcer
			when: GtCoderSourceCodeChanged
			do: [ :ann |
				draftPane removeFromParent.
				self writableRangeCoders do: [ :each | each announcer unsubscribe: draftPane ] ]
			for: draftPane ].
	container addChild: draftPane at: 2
]

{ #category : 'private' }
ElixirModuleCoder >> newTargetButtonFor: aDraftCoder [
	"Dropdown over the writable range; picking retargets the draft."
	| button |
	button := BrButton new
		aptitude: BrGlamorousButtonWithLabelAptitude;
		beSmallSize;
		label: aDraftCoder moduleCoder moduleName.
	button addAptitude: (BrGlamorousWithDropdownAptitude
		handle: [ BrButton new
			aptitude: BrGlamorousButtonWithLabelAptitude;
			beSmallSize;
			label: aDraftCoder moduleCoder moduleName ]
		content: [ BrVerticalPane new
			fitContent;
			margin: (BlInsets all: 5);
			addChildren: (self writableRangeCoders collect: [ :target |
				BrButton new
					aptitude: BrGlamorousButtonWithLabelAptitude;
					beSmallSize;
					label: target moduleName;
					action: [ :b |
						aDraftCoder moduleCoder: target.
						button label: target moduleName.
						b fireEvent: BrDropdownHideWish new ] ]) ]).
	^ button
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
ElixirModuleCoder >> buildFunctionsFilterBar: aStreamingModel [
	"GT filter-v2 bar: GtFilterItemsModel renders our filter models as native dropdowns
	 (Kind default-shown, others via +); the updater syncs picks into additionalFilters.
	 Also kept as functionStreamingModel so the source highlighter can read the active substrings."
	| aModel builder active defaults bar updater |
	self functionStreamingModel: aStreamingModel.
	aModel := GtFilterItemsModel new.
	builder := ElixirFunctionFiltersBuilder new coders: aStreamingModel.
	aModel availableFiltersBuilder: builder.
	active := (aStreamingModel additionalFilters
		collect: [ :f | f filterDescriptor2For: aStreamingModel ]) reject: [ :x | x isNil ].
	defaults := builder availableFilters
		select: [ :m | m isDefaultFilterModel and: [ (active includes: m) not ] ].
	aModel items: (Array streamContents: [ :s | s nextPutAll: active. s nextPutAll: defaults ]).
	bar := aModel asFiltersElement.
	updater := GtFilterMethodCodersAdditionalFiltersUpdater new
		coders: aStreamingModel;
		filtersModel: aModel.
	bar userData at: #elixirFilterUpdater put: updater.
	bar constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ].
	^ bar
]

{ #category : 'private' }
ElixirModuleCoder >> buildFunctionsViewElement [
	"I build the Functions tab. If focusLine is set, I set a scroll
	 target on the view model — the streaming element handles
	 scroll via list scrollToItemSuchThat:offset: when the matching
	 item loads (same pattern as GtPharoStreamingMethodsCoderElement).
	 Each function coder starts folded so the user scans the list."
	| container addRow streaming vm streamingElement focusStart filterBar |
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
	filterBar := self buildFunctionsFilterBar: streaming.
	"Wrap rather than sibling addRow: the draft pane inserts by index into container."
	^ BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ];
		addChild: filterBar;
		addChild: container;
		yourself
]

{ #category : 'private' }
ElixirModuleCoder >> buildSourceViewElement [
	"I build a self-refreshing container for the Source tab. The inner
	 coder is rebuilt whenever GtCoderSourceCodeChanged fires on me —
	 my #initialize subscribes weakly to the global bus and republishes
	 matching events as local GtCoderSourceCodeChanged, so the closure
	 captured here lives only as long as I do.
	 If focusLine is set, I scroll to that line after rendering."

	| container rebuild |
	container := BlElement new
			layout: BlLinearLayout vertical;
			constraintsDo: [ :c | 
				c horizontal matchParent.
				c vertical matchParent ].
	rebuild := [ | coderModel vm element |
		container removeChildren.
		coderModel := GtElixirCoderModel new.
		coderModel elixirLinkApplicationStrategy: LeElixirApplicationStrategy new.
		coderModel contextModuleName: moduleName.
		coderModel
			sourceCode: (GtCoderExplicitStringSource new source: self sourceCode).
		vm := coderModel asCoderViewModel.
		vm expanded: true.
		vm
			when: GtSourceCoderViewModelSaveRequested
			do: [ :ann | 
				self saveAndCompile: coderModel currentSourceString.
				ann consumed: true ].
		focusLine ifNotNil: [ :lines |
			| startLine source lineCount pos |
			startLine := lines isArray
				ifTrue: [ lines isEmpty ifTrue: [ nil ] ifFalse: [ lines first ] ]
				ifFalse: [ lines ].
			source := self sourceCode.
			lineCount := source lines size.
			(startLine isInteger and: [ startLine > 0 and: [ startLine <= lineCount ] ])
				ifTrue: [
					pos := 0.
					1 to: startLine - 1 do: [ :i |
						pos := pos + (source lines at: i) size + 1 ].
					vm moveCursorTo: pos.
					vm scrollToLine: startLine withCharacterPosition: 1 ] ].
		container addChild: vm asElement matchParent ].
	rebuild value.
	self announcer
		when: GtCoderSourceCodeChanged
		do: [ :ann | rebuild value ]
		for: self.
	^ container
]

{ #category : 'accessing' }
ElixirModuleCoder >> coderName [
	^ moduleName
]

{ #category : 'accessing' }
ElixirModuleCoder >> contextModuleName [
	"Common interface with GtElixirCoderModel and ElixirFunctionCoder
	 — lets context-aware tooling (styler, completion) call one
	 method regardless of which Elixir coder it's attached to."
	^ moduleName
]

{ #category : 'as yet unclassified' }
ElixirModuleCoder >> definesInterface [
	^ self interfaceFlags
		ifNil: [ false ]
		ifNotNil: [ :flags | (flags itemAt: 0) == true ]
]

{ #category : 'accessing' }
ElixirModuleCoder >> editorSessionId [
	"I return a unique session ID for this coder instance, with the
	 module's imports/aliases/requires loaded. The session is finalized
	 when this coder is GC'd."
	^ sessionId ifNil: [
		sessionId := 'editor_', moduleName, '_', UUID new asString.
		application evaluateAndWait:
			'GtBridge.Eval.Preamble.editor_session(', moduleName, ', "', sessionId, '")'.
		FinalizationRegistry default
			add: self
			finalizer: (BeamSessionFinalizer sessionId: sessionId application: application).
		sessionId ]
]

{ #category : 'accessing' }
ElixirModuleCoder >> focusFunctionTarget: aTarget [
	"I take an ElixirFunctionScrollTarget directly so callers that
	 know the function name+arity (BeamDocumentationObject>>gtCoderFor:)
	 can land on macro-generated entries that share startLine = 0."
	focusFunctionTarget := aTarget
]

{ #category : 'accessing' }
ElixirModuleCoder >> focusLine: aLineNumber [
	focusLine := aLineNumber
]

{ #category : 'accessing' }
ElixirModuleCoder >> functionEntries [
	"I return all function entries with line ranges, annotations,
	 and source text.

	 The per-module `BeamModuleSourceCache` is the canonical store —
	 a recompile event primes its `entries` list directly from the
	 announcement payload, so warm reads return the cache list with
	 no bridge round-trip.

	 On cold start (cache empty) I bridge-call
	 `Analysis.all_functions/1` and materialize any BeamProxyObject
	 so callers get a uniform iterable type.  Cold-start results are
	 NOT pushed into the cache — that's the cache's job, driven by
	 events; my fallback just keeps the UI alive until the first
	 recompile primes it."
	| cached result |
	cached := sourceCache entries.
	cached isNotEmpty ifTrue: [ ^ cached ].
	result := [ application evaluateAndWait:
		'GtBridge.Analysis.all_functions(', moduleName, ')' ]
		on: Error do: [ #() ].
	^ (result isKindOf: BeamProxyObject)
		ifTrue: [ result asList ]
		ifFalse: [ result ]
]

{ #category : 'accessing' }
ElixirModuleCoder >> functionStreamingModel [
	^ functionStreamingModel
]

{ #category : 'accessing' }
ElixirModuleCoder >> functionStreamingModel: aModel [
	functionStreamingModel := aModel
]

{ #category : 'gt-extensions' }
ElixirModuleCoder >> gtCallbacksViewFor: aView context: aContext [
	<gtElixirModuleView>
	"The interface's own contract: each callback with its full
	 @callback spec (a protocol shows its function list). Empty for
	 a module that defines neither."
	self definesInterface ifFalse: [ ^ aView empty ].
	^ aView columnedList
		title: 'Callbacks';
		priority: 44;
		items: [
			| defines names specs |
			defines := [ (self application evaluateAndWait:
				'GtBridge.Analysis.Interfaces.of_module(', self moduleName, ')')
				attributeAt: #defines ] on: Error do: [ nil ].
			defines
				ifNil: [ #() ]
				ifNotNil: [
					names := ((defines attributeAt: #callback_names)
						ifNil: [ defines attributeAt: #functions ])
						ifNil: [ #() ] ifNotNil: [ :l | l asList ].
					specs := (defines attributeAt: #callbacks)
						ifNil: [ #() ] ifNotNil: [ :l | l asList ].
					names withIndexCollect: [ :n :i |
						{ n asString.
						  (specs at: i ifAbsent: [ '' ]) asString } ] ] ];
		column: 'Callback' text: [ :each | each first ] width: 140;
		column: 'Spec' text: [ :each |
			' ' join: (each second lines collect: [ :l | l trimBoth ]) ];
		send: [ :each |
			| parts |
			parts := $/ split: each first.
			self application evaluateAndWait:
				'GtBridge.Documentation.for_function(', self moduleName,
				', :"', parts first, '", ', parts last, ')' ]
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
ElixirModuleCoder >> gtInterfacesViewFor: aView context: aContext [
	<gtElixirModuleView>
	"The module's interface drawing lives with the rest of its
	 static views; the atom and documentation proxies reach it
	 through their embedded coder."
	self hasInterfaces ifFalse: [ ^ aView empty ].
	^ (BeamMondrianHelpers
		interfacesDrawingFor: aView
		moduleExpr: self moduleName
		eval: [ :expr | self application evaluateAndWait: expr ])
		priority: 22
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

{ #category : 'gt-extensions' }
ElixirModuleCoder >> gtUsersViewFor: aView context: aContext [
	<gtElixirModuleView>
	"GT's coder calls an interface's consumers Users; for a module
	 that defines a behaviour or protocol I list its implementors.
	 Gated on the same memoized guard as the Callbacks tab."
	self definesInterface ifFalse: [ ^ aView empty ].
	^ aView columnedList
		title: 'Users';
		priority: 45;
		items: [
			| defines |
			defines := [ (self application evaluateAndWait:
				'GtBridge.Analysis.Interfaces.of_module(', self moduleName, ')')
				attributeAt: #defines ] on: Error do: [ nil ].
			defines
				ifNil: [ #() ]
				ifNotNil: [ BeamMondrianHelpers implementorsOf: defines ] ];
		column: 'Module' text: [ :each |
			(each attributeAt: #module) asString withoutPrefix: 'Elixir.' ];
		column: 'Implements' text: [ :each |
			(each attributeAt: #implements)
				ifNil: [ (each attributeAt: #for)
					ifNil: [ '' ] ifNotNil: [ :t | 'for ' , t asString ] ]
				ifNotNil: [ :l | ', ' join: (l asList collect: [ :s | s asString ]) ] ];
		send: [ :each |
			self application evaluateAndWait:
				'GtBridge.Documentation.for_module(',
				(each attributeAt: #module) asString, ')' ]
]

{ #category : 'as yet unclassified' }
ElixirModuleCoder >> hasFunctions [
	"Cheap guard: GtBridge.Analysis.has_functions?/1 answers from BEAM
	 metadata for normal modules (~1ms) and parses source only for
	 struct / macro-generated modules — instead of fetching and
	 serializing the whole function list just to test non-emptiness.
	 This guard runs eagerly when the coder builds its tab bar, so it
	 must be cheap or every module-coder open pays for it (white screen)."
	^ [ self application evaluateAndWait:
		'GtBridge.Analysis.has_functions?(', self moduleName, ')' ]
		on: Error do: [ false ]
]

{ #category : 'as yet unclassified' }
ElixirModuleCoder >> hasInterfaces [
	^ self interfaceFlags
		ifNil: [ false ]
		ifNotNil: [ :flags | (flags itemAt: 1) == true ]
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

{ #category : 'as yet unclassified' }
ElixirModuleCoder >> interfaceFlags [
	"One cheap eager eval gating the Interfaces, Callbacks and Users
	 tabs: {defines an interface, has any interface facts}. Memoized
	 like hasFunctions; nil on bridge error, which readers take as
	 false."
	^ interfaceFlags ifNil: [
		interfaceFlags := [ self application evaluateAndWait:
			'{GtBridge.Analysis.Interfaces.interface?(', self moduleName,
			'), GtBridge.Analysis.Interfaces.has_interfaces?(', self moduleName, ')}' ]
			on: Error do: [ nil ].
		(interfaceFlags isKindOf: BeamBridgeEvalError)
			ifTrue: [ interfaceFlags := nil ].
		interfaceFlags ]
]

{ #category : 'accessing' }
ElixirModuleCoder >> moduleName [
	^ moduleName
]

{ #category : 'accessing' }
ElixirModuleCoder >> moduleName: aString [
	"Canonicalize on input: strip the 'Elixir.' atom prefix that the
	 inspector path passes through (e.g. 'Elixir.LocalUpload.Uploads.Upload').
	 BeamModuleRecompiled events carry the bare form, so storing the
	 bare form here lets the per-module announcer key just match.

	 I also subscribe (weakly) to my module's per-module announcer here
	 — `initialize` can't because moduleName isn't known yet. If
	 reassigned to a different module, drop the prior subscription
	 first so I don't leak."
	| bare |
	bare := (aString beginsWith: 'Elixir.')
		ifTrue: [ aString copyFrom: 8 to: aString size ]
		ifFalse: [ aString ].
	self unsubscribeFromEntries.
	moduleName := bare.
	"Hold the per-module cache strongly via an ivar.  The class-side
	 registry is a WeakValueDictionary, so without a strong holder
	 the cache gets GC'd between the moduleName: setter return and
	 the next recompile event, which would silently drop the
	 BeamModuleEntriesUpdated chain on the floor."
	sourceCache := BeamModuleSourceCache for: moduleName.
	self subscribeToEntries
]

{ #category : 'namespace' }
ElixirModuleCoder >> existingNamespaceAncestors [
	"The ancestors that are loaded modules, nearest first."
	| ancestors loaded |
	ancestors := self class namespaceAncestorsOf: moduleName.
	loaded := BeamModuleResolution default loadedAmong: ancestors using: application.
	^ ancestors select: [ :each | loaded includes: each ]
]

{ #category : 'namespace' }
ElixirModuleCoder >> importedModuleNames [
	"Names this module explicitly imports, cached until the next recompile."
	| generation |
	generation := BeamModuleResolution default generation.
	(cachedImports notNil and: [ cachedImportsGeneration = generation ])
		ifTrue: [ ^ cachedImports ].
	cachedImportsGeneration := generation.
	cachedImports := [
		(application evaluateAndWait: 'GtBridge.Analysis.module_imports(', moduleName, ')')
			asList collect: [ :each | each asString ] ]
		on: Error do: [ #() ].
	^ cachedImports
]

{ #category : 'namespace' }
ElixirModuleCoder >> cachedImports: anArray [
	"Seed the import cache; examples use me to avoid the bridge."
	cachedImports := anArray.
	cachedImportsGeneration := BeamModuleResolution default generation
]

{ #category : 'namespace' }
ElixirModuleCoder >> relatedCoderFor: aModuleName [
	"One coder per related module, kept so its source cache stays alive."
	relatedCoders ifNil: [ relatedCoders := Dictionary new ].
	^ relatedCoders
		at: aModuleName
		ifAbsentPut: [ self class forModule: aModuleName application: application ]
]

{ #category : 'namespace' }
ElixirModuleCoder >> coderRangeUpTo: aModuleName [
	"Me, then each ancestor up to aModuleName, each followed by its imports.
	 The bare default — aModuleName is me — stays just me: imports join
	 only when the view widens. First occurrence of a module wins."
	| range seen add chain |
	aModuleName = moduleName ifTrue: [ ^ OrderedCollection with: self ].
	range := OrderedCollection new.
	seen := Set new.
	add := [ :coder |
		(seen includes: coder moduleName) ifFalse: [
			seen add: coder moduleName.
			range add: coder ] ].
	chain := OrderedCollection with: self.
	self existingNamespaceAncestors
		detect: [ :each | chain add: (self relatedCoderFor: each). each = aModuleName ]
		ifNone: [  ].
	chain do: [ :coder |
		add value: coder.
		coder importedModuleNames do: [ :each | add value: (self relatedCoderFor: each) ] ].
	^ range
]

{ #category : 'namespace' }
ElixirModuleCoder >> writableRangeCoders [
	"Range coders a new function can be appended to: those with a local
	 source file, me first."
	| range |
	range := functionStreamingModel
		ifNil: [ OrderedCollection with: self ]
		ifNotNil: [ :model | model rangeCoders ].
	^ range select: [ :each | each hasLocalSource ]
]

{ #category : 'subscriptions' }
ElixirModuleCoder >> onBeamModuleEntriesUpdated: anAnnouncement [
	"I translate the per-module cache's coarse `BeamModuleEntriesUpdated`
	 (fired once per recompile after the cache primes its entries
	 list) into my local `GtCoderSourceCodeChanged` for my own
	 announcer-based subscribers (Source tab rebuild, the function
	 streaming list).

	 The entries themselves live in `BeamModuleSourceCache`; I'm
	 just a translator from cache-event to local-coder-event.  I no
	 longer hold my own `cachedFunctionEntries` ivar — `functionEntries`
	 reads straight from the cache."
	self announce: (GtCoderSourceCodeChanged new coder: self)
]

{ #category : 'accessing' }
ElixirModuleCoder >> pageAliasSource [
	"Common interface with GtElixirCoderModel and ElixirFunctionCoder.
	 Module editors have no Lepiter page context."
	^ nil
]

{ #category : 'actions' }
ElixirModuleCoder >> remove [
	"I delete my source file and purge the BEAM module.  The bridge's
	 `purge_module/1` broadcasts `:source_removed` on the bus, which
	 the stream reader fires through `BeamEventAnnouncer` so caches
	 (`BeamModuleResolution`, `BeamModuleSourceCache`) drop their
	 derived state.  No UI-side announce."
	sourcePath asFileReference ensureDelete.
	self application
		evaluateAndWait: 'GtBridge.HotReload.purge_module(', moduleName, ')'
]

{ #category : 'actions' }
ElixirModuleCoder >> saveAndCompile: newSource [
	"I write source to disk and trigger compile.  Bridge-side events
	 (`:source_written`, `:recompiled`, `:compile_failed`) arrive over the
	 socket, dispatch through `BeamEventStreamReader`, and fire on
	 `BeamEventAnnouncer` — subscribers see them without me observing the
	 save.

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
		<< ('GtBridge.HotReload.reload("', sourcePath, '", Base.decode64!("', b64, '"))');
		sendAndWait.
	(result isKindOf: BeamBridgeEvalError) ifTrue: [
		Transcript
			show: 'ElixirModuleCoder >> saveAndCompile bridge error for ', moduleName, ': ';
			show: result printString;
			cr ].
	^ result
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
ElixirModuleCoder >> sourceCode [
	"Return '' when the source file is gone (post-`remove` rebuilds
	 hit me before the coder pane is dismissed)."
	| ref |
	sourcePath ifNil: [ ^ '' ].
	ref := sourcePath asFileReference.
	^ ref exists ifTrue: [ ref contents ] ifFalse: [ '' ]
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
	"Save (or delete, when newText is empty) one function by name/arity.
	 The bridge locates it in the source I pass, so the splice can't drift
	 like a cached range can. Skips if a save is already running."
	saving == true ifTrue: [ ^ self ].
	saving := true.
	[ self applySourceEdit:
		('GtBridge.Analysis.replace_function(', (self base64Expr: self sourceCode),
			', "', self moduleName, '", "', aName, '", ', anArity printString, ', ', (self base64Expr: newText), ')') ]
	ensure: [ saving := false ]
]

{ #category : 'subscriptions' }
ElixirModuleCoder >> subscribeToEntries [
	"I subscribe (weakly) to the per-module cache's coarse
	 `BeamModuleEntriesUpdated` event — fired once per recompile
	 after the cache primes its entries list — and translate it
	 into my local `GtCoderSourceCodeChanged` for downstream
	 consumers (Source tab rebuild, streaming list)."
	(BeamEventAnnouncer for: moduleName) weak
		when: BeamModuleEntriesUpdated
		send: #onBeamModuleEntriesUpdated:
		to: self
]

{ #category : 'actions' }
ElixirModuleCoder >> swapFunctions: entryA with: entryB [
	"Move: swap two functions by name/arity. The bridge recomputes the
	 ranges from the source I pass, so the splice can't drift like a cached
	 range can."
	^ self applySourceEdit:
		('GtBridge.Analysis.swap_functions(', (self base64Expr: self sourceCode),
			', "', self moduleName, '", "', (entryA attributeAt: #name) asString, '", ', (entryA attributeAt: #arity) printString,
			', "', (entryB attributeAt: #name) asString, '", ', (entryB attributeAt: #arity) printString, ')')
]

{ #category : 'subscriptions' }
ElixirModuleCoder >> unsubscribeFromEntries [
	"I drop my prior subscription before retargeting — otherwise I'd
	 leak listeners on the old module's announcer."
	moduleName ifNotNil: [
		(BeamEventAnnouncer for: moduleName) unsubscribe: self ]
]
