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

{ #category : 'private' }
LeElixirSnippetElement >> collectSiblingSourcesIn: snippets excluding: mySelf into: aCollection [
	snippets do: [ :snippet |
		(snippet ~~ mySelf and: [ snippet isKindOf: LeElixirSnippet ]) ifTrue: [
			snippet string ifNotNil: [ :src | aCollection add: src ] ].
		self collectSiblingSourcesIn: snippet children excluding: mySelf into: aCollection ]
]

{ #category : 'accessing' }
LeElixirSnippetElement >> onSnippetViewModelChanged [
	| pageSrc contextMod |
	super onSnippetViewModelChanged.

	self updateLanguageLabel.
	self coder
		elixirLinkApplicationStrategy: self serverStrategy.
	self coderViewModel
		viewPharoBindings: self snippetViewModel snippetBindings.
	pageSrc := self siblingSources.
	contextMod := self pageContextModuleName.
	self coder pageAliasSources: pageSrc.
	contextMod ifNotNil: [ self coder contextModuleName: contextMod ].
	"Force a re-style only when we injected context that the framework's
	 initial style: call couldn't have used — otherwise the unconditional
	 re-style races the layout pass and snippets sometimes disappear."
	(pageSrc isEmpty and: [ contextMod isNil ]) ifFalse: [
		self coder requestStyleSourceText ]
]

{ #category : 'private' }
LeElixirSnippetElement >> pageContextModuleName [
	"I return the Elixir module my page is for, so my coder can pull
	 the module's `alias`/`import` declarations: standalone pages
	 titled like an Elixir module use the title."
	| title |
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

{ #category : 'private' }
LeElixirSnippetElement >> siblingSources [
	"One string per sibling Elixir snippet, so each can be parsed on
	 its own.  Snapshot at view-model-change time."
	| page myself sources |
	page := [ self snippet page ] on: Error do: [ nil ].
	page ifNil: [ ^ #(  ) ].
	myself := self snippet.
	sources := OrderedCollection new.
	self collectSiblingSourcesIn: page children excluding: myself into: sources.
	^ sources
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
