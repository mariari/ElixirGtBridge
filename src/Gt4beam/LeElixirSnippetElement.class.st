Class {
	#name : 'LeElixirSnippetElement',
	#superclass : 'LeExternalEvaluatedSnippetElement',
	#instVars : [
		'serverStrategy'
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
		pharoBindings: self snippetViewModel snippetBindings
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
