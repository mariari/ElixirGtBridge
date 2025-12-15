Extension { #name : 'GtLlmLepiterContentExporter' }

{ #category : '*Gt4beam' }
GtLlmLepiterContentExporter >> visitElixirSnippet: aLeElixirSnippet [ 
	self codeSnippet: aLeElixirSnippet code labelled: 'elixir'.

	self visitChildren: aLeElixirSnippet
]
