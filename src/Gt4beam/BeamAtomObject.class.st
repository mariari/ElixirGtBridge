Class {
	#name : 'BeamAtomObject',
	#superclass : 'Object',
	#instVars : [
		'symbol'
	],
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'as yet unclassified' }
BeamAtomObject class >> leProxyTypeForPlaygroundPage [
	^ BeamAtomObject
]

{ #category : 'as yet unclassified' }
BeamAtomObject class >> new: aSymbol [
	^ self new symbol: aSymbol
]

{ #category : 'comparing' }
BeamAtomObject >> = aSymbol [
	"I should probably do this better"

	self class == aSymbol class ifFalse: [ ^ false ].
	^ self symbol = aSymbol symbol
]

{ #category : 'accessing' }
BeamAtomObject >> applicationAnalysis [
	"I return the ElixirApplicationAnalysis for my module, or nil.
	 I resolve through `LoadedModules.app_of`, not the raw
	 `Application.get_application`, so a brand-new module (absent from
	 every frozen app spec) still lands on its application."
	| appAtom sys |
	self isModuleAtom ifFalse: [ ^ nil ].
	appAtom := [ self evaluateAndWait:
		'GtBridge.Analysis.LoadedModules.app_of(', self resolve, ')' ]
		on: Error do: [ nil ].
	appAtom ifNil: [ ^ nil ].
	sys := ElixirSystemAnalysis onApplication: BeamLinkApplication uniqueInstance.
	^ sys applications
		detect: [ :each | each name symbol = appAtom symbol ]
		ifNone: [ nil ]
]

{ #category : 'as yet unclassified' }
BeamAtomObject >> determinePID [
	^ self evaluateAndWait: (self resolve , '|> Process.whereis()')
]

{ #category : 'accessing' }
BeamAtomObject >> elixirClass [
	"I return the Elixir module name for module atoms, or nil otherwise.
	 Used by GtElixirCoderModel's wrapSource:withSelf: to prepend
	 `import <Module>` to snippets that reference a module atom as self."
	^ self isModuleAtom ifTrue: [ symbol ]
]

{ #category : 'as yet unclassified' }
BeamAtomObject >> evaluateAndWait: aString [
	"I'm unsure how this works when we have multiple beam instances... Since this isn't related to any personal data"

	^ BeamLinkApplication uniqueInstance newCommandFactory
		<< aString;
		sendAndWait
]

{ #category : 'gt-actions' }
BeamAtomObject >> gtActionApplicationFor: anAction [
	<gtAction>
	"I add a toolbar button to open the Application analysis.
	 Only for module atoms that belong to a tracked application."
	^ anAction button
		icon: BrGlamorousVectorIcons hierarchy;
		label: 'Application';
		action: [ :aButton |
			self applicationAnalysis ifNotNil: [ :app |
				aButton phlow spawnObject: app ] ]
]

{ #category : 'views' }
BeamAtomObject >> gtBeamPrintFor: aView [
	<gtView>
	<gtBeamView>
	"I show the Elixir inspect() output for this atom."
	^ aView textEditor
		title: 'Print';
		priority: 115;
		aptitude: BrGlamorousCodeEditorAptitude;
		text: [ self evaluateAndWait: self resolve , ' |> inspect(pretty: true)' ]
]

{ #category : 'views' }
BeamAtomObject >> gtCoderFor: aView [
	<gtView>
	<gtBeamView>
	"I show the module coder for module atoms. Elixir modules get
	 the Elixir. prefix; Erlang modules use the bare atom name."
	| modName |
	self isModuleAtom ifFalse: [ ^ aView empty ].
	modName := symbol first isUppercase
		ifTrue: [ (symbol beginsWith: 'Elixir.')
			ifTrue: [ symbol ]
			ifFalse: [ 'Elixir.' , symbol ] ]
		ifFalse: [ ':' , symbol ].
	^ aView explicit
		title: 'Meta';
		priority: 199;
		stencil: [
			| coder |
			coder := ElixirModuleCoder
				forModule: modName
				application: BeamLinkApplication uniqueInstance.
			coder selfObject: self.
			coder asCoderViewModel asElement ]
]

{ #category : 'gt-extensions' }
BeamAtomObject >> gtDefaultInspectorTool [
	"I collect inspector modes — self (Atom) is implicit, declared
	 modes follow references transitively. R/P toggle always shows."
	| modes |
	modes := BeamInspectorModeCollector new
		fromObject: self;
		collect.
	^ BeamProxyToggleCompositeTool fromModes: modes
]

{ #category : 'views' }
BeamAtomObject >> gtModuleDocsView: aView [
	<gtView>
	<gtBeamView>
	| sections page |
	self isModuleAtom ifFalse: [ ^ aView empty ].
	sections := self evaluateAndWait:
		'GtBridge.Documentation.to_sections('
		, 'GtBridge.Documentation.for_module('
		, self resolve , '))'.
	sections isString ifFalse: [ ^ aView empty ].
	page := LePage named: self symbol.
	LeDatabase new addPage: page.
	(sections splitOn: '__SECTION__') do: [ :s |
		s trimBoth isEmpty ifFalse: [
			page addSnippet: (LeTextSnippet string: s trimBoth) ] ].
	^ aView explicit
		title: 'Documentation';
		priority: 3;
		stencil: [ page asPreviewElement vMatchParent ]
]

{ #category : 'inspector-modes' }
BeamAtomObject >> gtPidMode: aMode [
	<gtInspectorMode>
	| pid |
	pid := [ self determinePID ] on: Error do: [ nil ].
	(pid isNil or: [ pid isError ]) ifTrue: [ ^ aMode ].
	^ aMode
		name: 'Pid';
		priority: 10;
		object: pid;
		tool: (pid gtRemoteSideInspectorTool
			name: 'Pid';
			playgroundPageStrategy: LeInspectorPlaygroundProxyClassPageStrategy forRemoteProxySide;
			withLabelAndIconAptitude)
]

{ #category : 'gt-extensions' }
BeamAtomObject >> gtProxyInspectorContentFor: aView [
	"I build the Proxy tab's labelled content — generic GT views
	 only, no BEAM data views."
	^ GtPhlowLabelledViewBuilder new
		object: self;
		view: aView;
		context: GtPhlowContext new;
		viewsSelector: #gtViewsForProxySideInContext:;
		titleComputation: [ self symbol ];
		build
]

{ #category : 'gt-extensions' }
BeamAtomObject >> gtProxySideInspectorTool [
	"I return an inspector tool showing only GT wrapper views."
	^ GtInspectorTool
		forObject: self
		viewSelector: #gtProxyInspectorContentFor:
]

{ #category : 'gt-extensions' }
BeamAtomObject >> gtRemoteInspectorContentFor: aView [
	"I build the Remote tab's labelled content by collecting views
	 via gtViewsForRemoteSideInContext: — atom-specific views only,
	 no generic GT wrapper views (Raw, Print, Meta)."
	^ GtPhlowLabelledViewBuilder new
		object: self;
		view: aView;
		context: GtPhlowContext new;
		viewsSelector: #gtViewsForRemoteSideInContext:;
		titleComputation: [ self symbol ];
		build
]

{ #category : 'gt-extensions' }
BeamAtomObject >> gtRemoteSideInitialPlaygroundSnippet [
	^ LeElixirSnippet new
]

{ #category : 'gt-extensions' }
BeamAtomObject >> gtRemoteSideInspectorTool [
	"I return an inspector tool showing only atom-specific views
	 (Documentation, Playground) without generic GT wrapper views."
	^ GtInspectorTool
		forObject: self
		viewSelector: #gtRemoteInspectorContentFor:
]

{ #category : 'gt-extensions' }
BeamAtomObject >> gtSpotterActDefaultFrom: aSpotterElement [
	"I open my composite inspector tool in a pager instead of
	 the default plain GtInspector, preserving the R|P toggle."
	| tool |
	tool := self gtDefaultInspectorTool.
	BlSpace new
		inPager: tool;
		title: tool name;
		icon: tool icon;
		withSceneDriller;
		showFrom: aSpotterElement
]

{ #category : 'gt-extensions' }
BeamAtomObject >> gtViewsForProxySideInContext: aContext [
	"I collect views for Proxy mode — all views EXCEPT those
	 tagged <gtBeamView>. Shows Raw, Print, Meta."
	^ (self gtViewsInContext: aContext) reject: [ :each |
		each definingMethod compiledMethod hasPragmaNamed: #gtBeamView ]
]

{ #category : 'gt-extensions' }
BeamAtomObject >> gtViewsForRemoteSideInContext: aContext [
	"I collect views for Remote mode — only views tagged
	 <gtBeamView> (BEAM data views). Generic GT views (Raw,
	 Print, Meta) are excluded since they lack the pragma."
	^ (self gtViewsInContext: aContext) select: [ :each |
		each definingMethod compiledMethod hasPragmaNamed: #gtBeamView ]
]

{ #category : 'comparing' }
BeamAtomObject >> hash [
	^ self symbol hash hashMultiply
]

{ #category : 'gt-extensions' }
BeamAtomObject >> inspectorModeName [
	^ 'Atom'
]

{ #category : 'testing' }
BeamAtomObject >> isModuleAtom [
	"I return true for Elixir modules (uppercase) and Erlang
	 modules (lowercase, checked via Code.ensure_loaded? on the
	 BEAM). Erlang modules like :mnesia, :ets, :gen_server are
	 valid modules even though they start lowercase."

	symbol isEmpty ifTrue: [ ^ false ].
	symbol first isUppercase ifTrue: [ ^ true ].
	^ [ self evaluateAndWait: 'Code.ensure_loaded?(' , self resolve , ')' ]
		on: Error
		do: [ false ]
]

{ #category : 'as yet unclassified' }
BeamAtomObject >> printOn: aStream [
	self symbol printOn: aStream
]

{ #category : 'accessing' }
BeamAtomObject >> remoteClass [
	"I return the atom's module name for playground page keys."
	^ self elixirClass ifNil: [ symbol ]
]

{ #category : 'elixir - resolution' }
BeamAtomObject >> resolve [
	"I return the Elixir literal for this atom. Module atoms
	 (uppercase letter) are bare names; all others (including
	 underscore-prefixed like __meta__) get the : prefix."

	^ symbol first isUppercase
		ifTrue: [ symbol ]
		ifFalse: [ (symbol matchesRegex: '^[a-z_][a-zA-Z0-9_]*[?!]?$')
				ifTrue: [ ':' , symbol ]
				ifFalse: [ ':"' , symbol , '"' ] ]
]

{ #category : 'accessing' }
BeamAtomObject >> symbol [
	^ symbol
]

{ #category : 'accessing' }
BeamAtomObject >> symbol: anObject [
	symbol := anObject
]
