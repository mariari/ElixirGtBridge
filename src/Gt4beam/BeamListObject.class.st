Class {
	#name : 'BeamListObject',
	#superclass : 'BeamProxyObject',
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'as yet unclassified' }
BeamListObject class >> elixirClass [
	^ 'List'
]

{ #category : 'as yet unclassified' }
BeamListObject >> attributesAndValues [
	^ self asList withIndexCollect: [ :anItem :anIndex | anIndex -> anItem ]
]
