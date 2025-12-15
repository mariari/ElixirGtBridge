Extension { #name : 'LeHtmlVisitor' }

{ #category : '*Gt4beam' }
LeHtmlVisitor >> visitElixirSnippet: aSnippet [
	context html
		tag: #div
		attributes: (self
				classesFor: aSnippet
				withClasses: 'snippet textual-snippet code-snippet elixir-snippet')
		do: [ context html
				tag: #pre
				attributes: #('class' 'no_bottom_margin')
				with: aSnippet code ].
	^ self visitContent: aSnippet
]
