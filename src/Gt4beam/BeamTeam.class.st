Class {
	#name : 'BeamTeam',
	#superclass : 'BeamProxyObject',
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'as yet unclassified' }
BeamTeam class >> elixirClass [
	^ 'Team'
]

{ #category : 'as yet unclassified' }
BeamTeam >> gtTeamViewFor: aView [
	<gtView>
	^ aView list
		title: 'Team';
		items: [ (self attributeAt: 'members') asList ];
		itemText: [ :anItem | anItem attributeAt: 'name' ]
]
