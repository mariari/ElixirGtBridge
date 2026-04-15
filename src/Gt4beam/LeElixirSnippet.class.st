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

{ #category : 'instance creation' }
LeElixirSnippet class >> playgroundFor: anObject [
	"I build a fresh snippet element pre-bound to anObject as self,
	 suitable for use as an inspector Playground view stencil. Shared
	 by BeamProxyObject and BeamAtomObject so both kinds of inspected
	 values get the same scratch space."
	| snippet vm |
	snippet := self new.
	snippet code: 'self'.
	vm := snippet asSnippetViewModel.
	vm inspectorSelfObject: anObject.
	^ vm asSnippetElement matchParent
]

{ #category : 'lepiter-store' }
LeElixirSnippet class >> leJsonV3Name [

	^ 'elixirSnippet'
]

{ #category : 'lepiter-store' }
LeElixirSnippet class >> leJsonV4Name [

	^ 'elixirSnippet'
]

{ #category : 'accessing' }
LeElixirSnippet >> newCoder [
	^ GtElixirCoderModel new
]

{ #category : 'converting' }
LeElixirSnippet >> asSnippetViewModel [
	<return: #LeSnippetViewModel>
	^ LeElixirSnippetViewModel new snippetModel: self
]

{ #category : 'visiting' }
LeElixirSnippet >> acceptVisitor: aVisitor [

	^ aVisitor visitElixirSnippet: self
]
