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
	| formattedItems rawItems textMap |
	formattedItems := (self rawData attributeAt: #items) asList.
	rawItems := (self rawData attributeAt: #rawItems) asList.
	textMap := IdentityDictionary new: rawItems size.
	rawItems withIndexDo: [ :item :idx |
		textMap at: item put: (formattedItems at: idx) ].
	view items: [ rawItems ].

	(self rawData attributeAt: #columns) asList
		withIndexDo: [ :aColumn :anIndex |
			view
				column: (aColumn attributeAt: #title)
				text: [ :item | (textMap at: item) asList at: anIndex ] ]
]

{ #category : 'as yet unclassified' }
GtBeamColumnedListViewDeclaration >> viewName [
	^ #columnedList
]
