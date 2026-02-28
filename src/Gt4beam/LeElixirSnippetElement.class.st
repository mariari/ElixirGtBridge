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

{ #category : 'accessing' }
LeElixirSnippetElement >> onSnippetViewModelChanged [
	super onSnippetViewModelChanged.

	self updateLanguageLabel.
	self coder
		elixirLinkApplicationStrategy: self serverStrategy;
		pharoBindings: self snippetViewModel snippetBindings.
	self coderViewModel
		viewPharoBindings: self snippetViewModel snippetBindings
]

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
