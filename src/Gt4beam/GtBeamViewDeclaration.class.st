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
	self
		allSubclassesDo: [ :aSubclass | 
			aSubclass remoteName = (aData attributeAt: (BeamAtomObject new: #viewName))
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
		title: (self rawData attributeAt: (BeamAtomObject new: #title));
		priority: (self rawData attributeAt:  (BeamAtomObject new: #priority)).

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
