Class {
	#name : 'GtBeamViewDeclaration',
	#superclass : 'Object',
	#instVars : [
		'rawData'
	],
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'as yet unclassified' }
GtBeamViewDeclaration class >> fromRawData: aData [
	| name |
	name := aData attributeAt: #viewName.
	self
		allSubclassesDo: [ :aSubclass |
			aSubclass remoteName = name
				ifTrue: [ ^ aSubclass new rawData: aData ] ].

	^ self error: 'Unknown view'
]

{ #category : 'as yet unclassified' }
GtBeamViewDeclaration class >> remoteName [
	^ self subclassResponsibility
]

{ #category : 'as yet unclassified' }
GtBeamViewDeclaration >> asView [
	| view |
	view := GtPhlowView empty perform: self viewName.

	view
		title: (self rawData attributeAt: #title);
		priority: (self rawData attributeAt: #priority).

	self treatView: view.

	^ view
]

{ #category : 'accessing' }
GtBeamViewDeclaration >> rawData [
	^ rawData
]

{ #category : 'accessing' }
GtBeamViewDeclaration >> rawData: anObject [
	rawData := anObject
]

{ #category : 'as yet unclassified' }
GtBeamViewDeclaration >> treatView: view [ 
]

{ #category : 'as yet unclassified' }
GtBeamViewDeclaration >> viewName [
	^ self subclassResponsibility
]
