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
	| formattedItems |
	formattedItems := (self rawData attributeAt: #items) asList.
	view items: [ (self rawData attributeAt: #rawItems) asList ].

	(self rawData attributeAt: #columns) asList
		withIndexDo: [ :aColumn :anIndex | 
			view
				column: (aColumn attributeAt: #title)
				text: [ :item | 
					(formattedItems at: ((self rawData attributeAt: #rawItems) asList indexOf: item))
						asList at: anIndex ] ]
]

{ #category : 'as yet unclassified' }
GtBeamColumnedListViewDeclaration >> viewName [
	^ #columnedList
]
