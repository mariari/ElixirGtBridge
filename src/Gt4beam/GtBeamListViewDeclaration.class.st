Class {
	#name : 'GtBeamListViewDeclaration',
	#superclass : 'GtBeamViewDeclaration',
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'as yet unclassified' }
GtBeamListViewDeclaration class >> remoteName [
	^ 'GtPhlowListViewSpecification'
]

{ #category : 'as yet unclassified' }
GtBeamListViewDeclaration >> treatView: aView [
	aView
		items: [ (self rawData attributeAt: (BeamAtomObject new: #items)) asList ]
]

{ #category : 'as yet unclassified' }
GtBeamListViewDeclaration >> viewName [
	^ #list
]
