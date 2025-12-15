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
	view text: [ self rawData attributeAt: (BeamAtomObject new: #string) ]
]

{ #category : 'as yet unclassified' }
GtBeamTextEditorViewDeclaration >> viewName [
	^ #textEditor
]
