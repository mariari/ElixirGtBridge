Class {
	#name : 'GtBeamColumnedTreeViewDeclaration',
	#superclass : 'GtBeamViewDeclaration',
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'as yet unclassified' }
GtBeamColumnedTreeViewDeclaration class >> remoteName [
	^ 'GtPhlowColumnedTreeViewSpecification'
]

{ #category : 'as yet unclassified' }
GtBeamColumnedTreeViewDeclaration >> treatView: view [
	view
		items: [ (self rawData attributeAt: (BeamAtomObject new: #items)) asList ];
		children: [ :item | (item attributeAt: (BeamAtomObject new: #children)) asList ].

	(self rawData attributeAt: (BeamAtomObject new: #columns)) asList
		withIndexDo: [ :aColumn :anIndex | 
			view
				column: (aColumn attributeAt: #title)
				text: [ :item | (item attributeAt: (BeamAtomObject new: #values)) asList at: anIndex ] ]
]

{ #category : 'as yet unclassified' }
GtBeamColumnedTreeViewDeclaration >> viewName [
	^ #columnedTree
]
