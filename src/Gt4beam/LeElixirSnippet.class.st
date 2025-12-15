Class {
	#name : 'LeElixirSnippet',
	#superclass : 'LeCodeSnippet',
	#category : 'Gt4beam-Lepiter',
	#package : 'Gt4beam',
	#tag : 'Lepiter'
}

{ #category : 'api - accessing menu' }
LeElixirSnippet class >> contextMenuItemSpecification [
	<leSnippetSpecification>
	^ LeContextMenuItemSpecification new
		snippetClass: self;
		title: 'Elixir'
]

{ #category : 'lepiter-store' }
LeElixirSnippet class >> leJsonV3Name [

	^ 'elixirSnippet'
]

{ #category : 'lepiter-store' }
LeElixirSnippet class >> leJsonV4Name [

	^ 'elixirSnippet'
]

{ #category : 'visiting' }
LeElixirSnippet >> acceptVisitor: aVisitor [

	^ aVisitor visitElixirSnippet: self
]

{ #category : 'converting' }
LeElixirSnippet >> asSnippetViewModel [
	<return: #LeSnippetViewModel>
	^ LeElixirSnippetViewModel new snippetModel: self
]

{ #category : 'accessing' }
LeElixirSnippet >> newCoder [
	^ GtElixirCoderModel new
]
