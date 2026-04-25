Class {
	#name : 'ElixirCodeNavigationExamples',
	#superclass : 'Object',
	#category : 'Gt4beam-Examples',
	#package : 'Gt4beam',
	#tag : 'Examples'
}

{ #category : 'examples - setup' }
ElixirCodeNavigationExamples >> application [
	"I return the running BEAM application."
	<gtExample>
	| app |
	app := BeamLinkApplication uniqueInstance.
	self assert: app isRunning.
	^ app
]

{ #category : 'examples - navigation' }
ElixirCodeNavigationExamples >> cmBareFunctionShowsImplementors [
	"I verify C-m on a bare function name spawns an implementors list."
	<gtExample>
	| coder spawned |
	coder := self navigationCoderOver: '  start_link(opts)'.
	spawned := self listenForSpawnOn: coder.
	coder browseImplementorsAt: 5 requesterObject: nil.
	self assert: spawned contents isNotNil.
	self assert: spawned contents class name equals: 'ElixirSearchFilter'.
	self assert: spawned contents gtDisplayString equals: 'start_link implementors'.
	^ spawned contents
]

{ #category : 'examples - navigation' }
ElixirCodeNavigationExamples >> cmNavigatesToFunction [
	"I verify C-m on a fully qualified call spawns a Documentation
	 object scoped to the specific function source_file/1, not just
	 any documentation object."
	<gtExample>
	| coder spawned docs query |
	coder := self qualifiedDottedCoder.
	spawned := self listenForSpawnOn: coder.
	coder browseImplementorsAt: 22 requesterObject: nil.
	docs := spawned contents.
	self assert: docs isNotNil description: 'Should have spawned'.
	self assert: docs class name equals: 'BeamDocumentationObject'.
	query := docs attributeAt: #query.
	self assert: (query itemAt: 0) symbol equals: #function.
	self assert: (query itemAt: 1) symbol equals: #'Elixir.GtBridge.Resolve'.
	self assert: (query itemAt: 2) symbol equals: #source_file.
	self assert: (query itemAt: 3) equals: 1.
	^ docs
]

{ #category : 'examples - navigation' }
ElixirCodeNavigationExamples >> cnShowsReferences [
	"I verify C-n on a qualified call spawns a references filter
	 titled for source_file specifically — wrong target would fail."
	<gtExample>
	| coder spawned filter |
	coder := self qualifiedDottedCoder.
	spawned := self listenForSpawnOn: coder.
	coder browseReferencesAt: 22 requesterObject: nil.
	filter := spawned contents.
	self assert: filter isNotNil.
	self assert: filter class name equals: 'ElixirSearchFilter'.
	self assert: filter gtDisplayString equals: 'GtBridge.Resolve.source_file references'.
	self assert: (filter instVarNamed: 'items') isNotNil
		description: 'Filter should carry the references list from BEAM'.
	^ filter
]

{ #category : 'examples - navigation' }
ElixirCodeNavigationExamples >> cursorDetectsQualifiedCall [
	"I verify detectElixirFunctionAt: splits Module.function correctly
	 by composing on qualifiedDottedCoder and pointing at the `(`."
	<gtExample>
	| result |
	result := nil.
	self qualifiedDottedCoder
		detectElixirFunctionAt: 22
		ifFound: [ :mod :fn | result := { mod. fn } ]
		ifNone: [ result := #none ].
	self assert: result first equals: 'GtBridge.Resolve'.
	self assert: result second equals: 'source_file'.
	^ result
]

{ #category : 'examples - setup' }
ElixirCodeNavigationExamples >> listenForSpawnOn: aCoder [
	"I attach a spawn listener to aCoder and return a holder
	 whose `contents` becomes the next spawned object. Lets
	 navigation examples share the announcer-subscription preamble."
	| holder |
	holder := ValueHolder new.
	aCoder announcer
		when: GtCoderObjectSpawnRequest
		do: [ :ann | holder contents: ann object ]
		for: aCoder.
	^ holder
]

{ #category : 'examples - setup' }
ElixirCodeNavigationExamples >> moduleCoder [
	"I return an ElixirModuleCoder for GtBridge.Eval."
	<gtExample>
	| app coder |
	app := self application.
	coder := ElixirModuleCoder new
		moduleName: 'GtBridge.Eval';
		sourcePath: (app evaluateAndWait: 'GtBridge.Resolve.source_file(GtBridge.Eval)');
		application: app.
	self assert: coder hasFunctions.
	self assert: coder hasLocalSource.
	^ coder
]

{ #category : 'examples - setup' }
ElixirCodeNavigationExamples >> moduleCoderWithFocusLine [
	"I return a module coder with focusLine set to a known function.
	 Looks up eval's actual arity and line range dynamically."
	<gtExample>
	| app coder fns evalFn startLine |
	app := self application.
	fns := (app evaluateAndWait:
		'GtBridge.Analysis.all_functions(GtBridge.Eval)') asList.
	evalFn := fns detect: [ :f |
		(f attributeAt: #name) asString = 'eval' ] ifNone: [ nil ].
	self assert: evalFn isNotNil description: 'eval should exist'.
	startLine := (evalFn attributeAt: #start) asInteger.
	self assert: startLine > 1 description: 'eval should not be at line 1'.
	coder := self moduleCoder.
	coder focusLine: { startLine. (evalFn attributeAt: #end_line) asInteger }.
	^ coder
]

{ #category : 'examples - setup' }
ElixirCodeNavigationExamples >> navigationCoderOver: aSourceString [
	"I return a fresh GtElixirCoderModel wired with the Elixir
	 application strategy and the given source. Composable preamble
	 for navigation and cursor-detection examples."
	^ GtElixirCoderModel new
		elixirLinkApplicationStrategy: LeElixirApplicationStrategy new;
		sourceCode: (GtCoderExplicitStringSource new source: aSourceString);
		yourself
]

{ #category : 'examples - setup' }
ElixirCodeNavigationExamples >> qualifiedDottedCoder [
	"I return a coder over `GtBridge.Resolve.source_file(mod)`,
	 reused by C-m, C-n, and cursor-detection examples that target
	 a qualified call. Asserts the source is wired in during setup."
	<gtExample>
	| coder |
	coder := self navigationCoderOver: 'GtBridge.Resolve.source_file(mod)'.
	self assert: coder currentSourceString equals: 'GtBridge.Resolve.source_file(mod)'.
	^ coder
]

