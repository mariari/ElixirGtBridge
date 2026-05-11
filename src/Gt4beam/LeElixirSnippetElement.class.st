Class {
	#name : 'LeElixirSnippetElement',
	#superclass : 'LeExternalEvaluatedSnippetElement',
	#instVars : [
		'serverStrategy'
	],
	#classVars : [
		'SessionMap'
	],
	#category : 'Gt4beam-Lepiter',
	#package : 'Gt4beam',
	#tag : 'Lepiter'
}

{ #category : 'private' }
LeElixirSnippetElement class >> sessionIdFor: aBindings [
	"I return (or create) a session UUID for a given shared bindings object.
	Identity-keyed: same object → same ID, different objects → different IDs."
	^ self sessionMap
		at: aBindings
		ifAbsentPut: [ UUID new asString ]
]

{ #category : 'private' }
LeElixirSnippetElement class >> sessionMap [
	^ SessionMap ifNil: [ SessionMap := WeakIdentityKeyDictionary new ]
]

{ #category : 'accessing' }
LeElixirSnippetElement >> onSnippetViewModelChanged [
	super onSnippetViewModelChanged.

	self updateLanguageLabel.
	self coder
		elixirLinkApplicationStrategy: self serverStrategy.
	self coderViewModel
		viewPharoBindings: self snippetViewModel snippetBindings.
	self snippetViewModel inspectorSelfObject ifNotNil: [ :obj |
		self coderViewModel selfObject: obj ].
	self pageContextModuleName ifNotNil: [ :mod |
		self coder contextModuleName: mod.
		"Force a re-style: the framework invoked style: before this
		 setter ran, so existing |> attributes were resolved with no
		 context.  The cache key now differs but Bloc won't re-call
		 style until the text changes, so push a fresh style cycle."
		self coder requestStyleSourceText ]
]

{ #category : 'private' }
LeElixirSnippetElement >> pageContextModuleName [
	"I return the Elixir module my page is for, so my coder can pull
	 the module's `alias`/`import` declarations.  Two sources:

	 1. Inspector playgrounds for a `BeamProxyObject` use the proxy's
	    `elixirClass`.
	 2. Standalone pages titled like an Elixir module use the title."
	| selfObj title |
	selfObj := [ self snippetViewModel inspectorSelfObject ] on: Error do: [ nil ].
	(selfObj isKindOf: BeamProxyObject) ifTrue: [
		^ [ selfObj elixirClass ] on: Error do: [ nil ] ].
	title := [ self snippet page title ] on: Error do: [ nil ].
	(title isString and: [ title matchesRegex: '^[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*$' ])
		ifFalse: [ ^ nil ].
	^ title
]

{ #category : 'accessing' }
LeElixirSnippetElement >> serverStrategy [
	^ serverStrategy
		ifNil: [ serverStrategy := LeElixirApplicationStrategy new content: self snippet ]
]

{ #category : 'accessing' }
LeElixirSnippetElement >> updateLanguageLabel [
	| serverAddress label |

	serverAddress := self serverStrategy applicationSettings serverSocketAddress.
	label := String streamContents: [ :stream |
		stream
			<< 'Elixir @ ';
			<< serverAddress ipOrName;
			<< ':';
			print: serverAddress port ].
	languageElement text: (label asRopedText glamorousRegularFont foreground: BrGlamorousColors textMarkupColor).
]
