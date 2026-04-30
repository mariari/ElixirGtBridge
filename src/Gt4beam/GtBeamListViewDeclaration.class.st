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
	| formattedItems rawItems textMap |
	formattedItems := (self rawData attributeAt: #items) asList.
	rawItems := (self rawData attributeAt: #rawItems) asList.
	textMap := IdentityDictionary new: rawItems size.
	rawItems withIndexDo: [ :item :idx |
		textMap at: item put: (formattedItems at: idx) ].
	aView
		items: [ rawItems ];
		itemText: [ :item | textMap at: item ]
]

{ #category : 'as yet unclassified' }
GtBeamListViewDeclaration >> viewName [
	^ #list
]
