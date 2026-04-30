Class {
	#name : 'LeElixirSnippetViewModel',
	#superclass : 'LeCodeSnippetViewModel',
	#category : 'Gt4beam-Lepiter',
	#package : 'Gt4beam',
	#tag : 'Lepiter'
}

{ #category : 'accessing' }
LeElixirSnippetViewModel >> initializeCoderAddOns: aCoderViewModel [
	"Initialise the keyboard shortcuts in the code editor"

	aCoderViewModel
		"Create New snippet (after the current snippet)"
		addShortcut: (LeSnippetSplitSnippetShortcut new combination: (self keyboardShortcut: #SplitSnippet));
		"Delete previous character, or merge with previous snippet"
		addShortcut: (LeSnippetDeletePreviousShortcut new combination: (self keyboardShortcut: #DeletePrevious));
		"Indent LeSnippet"
		addShortcut: (LeSnippetIndentSnippetShortcut new combination: (self keyboardShortcut: #IndentSnippet));
		"Unindent LeSnippet"
		addShortcut: (LeSnippetUnindentSnippetShortcut new combination: (self keyboardShortcut: #UnindentSnippet));
		"Move Snippet up"
		addShortcut: (LeSnippetMoveSnippetUpShortcut new combination: (self keyboardShortcut: #MoveSnippetUp));
		"Move Snippet down"
		addShortcut: (LeSnippetMoveSnippetDownShortcut new combination: (self keyboardShortcut: #MoveSnippetDown))
]

{ #category : 'accessing' }
LeElixirSnippetViewModel >> inspectorSelfObject [
	"I return the inspected object from the shared snippet context,
	or nil if not in an inspector."
	^ sharedContext ifNotNil: [ :ctx | ctx selfObject ]
]

{ #category : 'accessing' }
LeElixirSnippetViewModel >> inspectorSelfObject: anObject [
	"I bind anObject as the inspected self on my shared snippet context,
	 creating a minimal context first if one isn't already in place. Used
	 to wire up standalone snippets in inspector playgrounds. The ivar is
	 written via instVarNamed: because LeAbstractSnippetViewModel has no
	 public setter for sharedContext, and the getter stays private."
	sharedContext
		ifNil: [ self instVarNamed: 'sharedContext' put: LeSharedSnippetContext new ].
	sharedContext selfObject: anObject
]

{ #category : 'accessing' }
LeElixirSnippetViewModel >> snippetElementClass [
	^ LeElixirSnippetElement
]
