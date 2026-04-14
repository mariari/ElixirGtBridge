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

{ #category : 'rendering' }
GtBeamMondrianViewDeclaration >> treatView: view [
	| nodes adjacency layoutName items |
	nodes := (self rawData attributeAt: #nodes) asList.
	adjacency := (self rawData attributeAt: #adjacency) asList.
	layoutName := self rawData attributeAt: #layout.
	items := nodes collect: [ :aNode | aNode attributeAt: #object ].
	view painting: [ :aMondrian |
		aMondrian nodes
			stencil: [ :anItem |
				| idx label colorHex color el |
				idx := items identityIndexOf: anItem.
				label := ((nodes at: idx) attributeAt: #label) asString.
				colorHex := [ ((nodes at: idx) attributeAt: #color) asString ]
					on: Error do: [ nil ].
				color := (colorHex notNil and: [ colorHex ~= 'nil' ])
					ifTrue: [ Color fromHexString: colorHex ]
					ifFalse: [ Color white ].
				el := BrHorizontalPane new
					geometry: (BlRoundedRectangleGeometry cornerRadius: 3);
					border: (BlBorder paint: color darker width: 1);
					background: color;
					padding: (BlInsets all: 5);
					addChild: (BrLabel new
						text: label;
						aptitude: BrGlamorousLabelAptitude);
					constraintsDo: [ :c |
						c horizontal fitContent.
						c vertical fitContent ].
				el addEventHandlerOn: BlClickEvent do: [ :evt |
					evt consumed: true.
					evt currentTarget phlow spawnObject: anItem ].
				el ];
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
