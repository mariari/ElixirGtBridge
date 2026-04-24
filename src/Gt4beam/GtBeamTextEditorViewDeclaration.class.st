Class {
	#name : 'GtBeamTextEditorViewDeclaration',
	#superclass : 'GtBeamViewDeclaration',
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'as yet unclassified' }
GtBeamTextEditorViewDeclaration class >> remoteName [
	^ 'GtPhlowTextEditorViewSpecification'
]

{ #category : 'testing' }
GtBeamTextEditorViewDeclaration >> isMarkdown [
	^ (self rawData attributeAt: #markdown) = true
]

{ #category : 'private' }
GtBeamTextEditorViewDeclaration >> treatMarkdownView: view [
	| string page |
	string := self rawData attributeAt: #string.
	page := LePage named: (self rawData attributeAt: #title).
	LeDatabase new addPage: page.
	(string splitOn: '__SECTION__') do: [ :s |
		s trimBoth isEmpty ifFalse: [
			page addSnippet: (LeTextSnippet string: s trimBoth) ] ].
	view stencil: [ page asPreviewElement vMatchParent ]
]

{ #category : 'private' }
GtBeamTextEditorViewDeclaration >> treatTextView: view [
	view text: [
		| text |
		text := (self rawData attributeAt: #string) asRopedText.
		{
			#monospace -> [ :v | v ifTrue: [ text glamorousCodeFont ] ].
			#fontSize -> [ :v | text fontSize: v ]
		} do: [ :assoc |
			(self rawData attributeAt: assoc key)
				ifNotNil: [ :v | assoc value value: v ] ].
		text ]
]

{ #category : 'as yet unclassified' }
GtBeamTextEditorViewDeclaration >> treatView: view [
	self isMarkdown
		ifTrue: [ self treatMarkdownView: view ]
		ifFalse: [ self treatTextView: view ]
]

{ #category : 'as yet unclassified' }
GtBeamTextEditorViewDeclaration >> viewName [
	self isMarkdown
		ifTrue: [ ^ #explicit ]
		ifFalse: [ ^ #textEditor ]
]
