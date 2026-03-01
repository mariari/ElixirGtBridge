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

{ #category : 'as yet unclassified' }
GtBeamTextEditorViewDeclaration >> treatView: view [
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
GtBeamTextEditorViewDeclaration >> viewName [
	^ #textEditor
]
