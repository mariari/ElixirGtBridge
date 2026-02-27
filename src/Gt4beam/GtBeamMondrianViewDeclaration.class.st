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
	| nodes adjacency layoutName objects items |
	nodes := (self rawData attributeAt: #nodes) asList.
	adjacency := (self rawData attributeAt: #adjacency) asList.
	layoutName := self rawData attributeAt: #layout.
	objects := (self rawData attributeAt: #objects)
		ifNotNil: [ :o | o asList ].
	items := objects ifNil: [ nodes ].
	view painting: [ :aMondrian |
		aMondrian nodes
			stencil: [ :anItem |
				| idx label |
				idx := items identityIndexOf: anItem.
				label := ((nodes at: idx) attributeAt: #label) asString.
				BrHorizontalPane new
					geometry: (BlRoundedRectangleGeometry cornerRadius: 3);
					border: (BlBorder paint: Color lightGray width: 1);
					background: Color white;
					padding: (BlInsets all: 5);
					addChild: (BrLabel new
						text: label;
						aptitude: BrGlamorousLabelAptitude);
					constraintsDo: [ :c |
						c horizontal fitContent.
						c vertical fitContent ] ];
			with: items.
		aMondrian edges
			connectToAll: [ :anItem |
				| idx |
				idx := items identityIndexOf: anItem.
				(adjacency at: idx) asList
					collect: [ :childIdx | items at: childIdx + 1 ] ].
		aMondrian layout perform: layoutName asSymbol ]
]

{ #category : 'as yet unclassified' }
GtBeamMondrianViewDeclaration >> viewName [
	^ #mondrian
]
