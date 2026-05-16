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
	| pageSrc contextMod |
	super onSnippetViewModelChanged.

	self updateLanguageLabel.
	self coder
		elixirLinkApplicationStrategy: self serverStrategy.
	self coderViewModel
		viewPharoBindings: self snippetViewModel snippetBindings.
	self snippetViewModel inspectorSelfObject ifNotNil: [ :obj |
		self coderViewModel selfObject: obj ].
	pageSrc := self siblingAliasSource.
	contextMod := self pageContextModuleName.
	self coder pageAliasSource: pageSrc.
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

{ #category : 'private' }
LeElixirSnippetElement >> siblingAliasSource [
	"I concatenate every other Elixir snippet on my page so the
	 styler's existing `extractAliasesFrom:` can pick up declarations
	 introduced elsewhere on the page.  Snapshot at view-model-change
	 time; editing a sibling later won't refresh me until I remount."
	| page myself stream |
	page := [ self snippet page ] on: Error do: [ nil ].
	page ifNil: [ ^ '' ].
	myself := self snippet.
	stream := WriteStream on: String new.
	self collectSiblingSourcesIn: page children excluding: myself into: stream.
	^ stream contents
]

{ #category : 'private' }
LeElixirSnippetElement >> collectSiblingSourcesIn: snippets excluding: mySelf into: stream [
	snippets do: [ :snippet |
		(snippet ~~ mySelf and: [ snippet isKindOf: LeElixirSnippet ]) ifTrue: [
			snippet string ifNotNil: [ :src |
				stream nextPutAll: src; nextPut: Character lf ] ].
		self collectSiblingSourcesIn: snippet children excluding: mySelf into: stream ]
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
