Class {
	#name : 'GtBeamMondrianViewDeclaration',
	#superclass : 'GtBeamViewDeclaration',
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'as yet unclassified' }
GtBeamMondrianViewDeclaration class >> remoteName [
	^ 'GtPhlowMondrianViewSpecification'
]

{ #category : 'as yet unclassified' }
GtBeamMondrianViewDeclaration >> treatView: view [
	| nodes adjacency layoutName |
	nodes := (self rawData attributeAt: #nodes) asList.
	adjacency := (self rawData attributeAt: #adjacency) asList.
	layoutName := self rawData attributeAt: #layout.
	view painting: [ :aMondrian |
		aMondrian nodes
			stencil: [ :aNode |
				BrLabel new
					text: (aNode attributeAt: #label);
					aptitude: BrGlamorousLabelAptitude ];
			with: nodes.
		aMondrian edges
			connectToAll: [ :aNode |
				| idx |
				idx := nodes identityIndexOf: aNode.
				(adjacency at: idx) asList
					collect: [ :childIdx | nodes at: childIdx + 1 ] ].
		aMondrian layout perform: layoutName asSymbol ]
]

{ #category : 'as yet unclassified' }
GtBeamMondrianViewDeclaration >> viewName [
	^ #mondrian
]
