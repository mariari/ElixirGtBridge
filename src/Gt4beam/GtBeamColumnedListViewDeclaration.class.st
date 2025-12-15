Class {
	#name : 'GtBeamColumnedListViewDeclaration',
	#superclass : 'GtBeamViewDeclaration',
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'as yet unclassified' }
GtBeamColumnedListViewDeclaration class >> remoteName [
	^ 'GtPhlowColumnedListViewSpecification'
]

{ #category : 'as yet unclassified' }
GtBeamColumnedListViewDeclaration >> treatView: view [
	view items: [ (self rawData attributeAt: #items) asList ].

	(self rawData attributeAt: #columns) asList
		withIndexDo: [ :aColumn :anIndex | view column: (aColumn attributeAt: #title) text: [ :item | item asList at: anIndex ] ]
]

{ #category : 'as yet unclassified' }
GtBeamColumnedListViewDeclaration >> viewName [
	^ #columnedList
]
