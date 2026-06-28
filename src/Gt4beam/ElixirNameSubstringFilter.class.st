Class {
	#name : 'ElixirNameSubstringFilter',
	#superclass : 'ElixirFunctionsFilter',
	#instVars : [
		'substring'
	],
	#category : 'Gt4beam-Filters',
	#package : 'Gt4beam',
	#tag : 'Filters'
}

{ #category : 'instance creation' }
ElixirNameSubstringFilter class >> forSubstring: aString [
	^ self new substring: aString
]

{ #category : 'descriptors' }
ElixirNameSubstringFilter class >> globalFilterDescriptor2 [
	^ GtFilterTextModel new
		creator: [ :value | self forSubstring: value ];
		named: 'Name';
		order: 15;
		yourself
]

{ #category : 'descriptors' }
ElixirNameSubstringFilter >> filterDescriptor2For: aCoder [
	^ (super filterDescriptor2For: aCoder)
		ifNotNil: [ :aFilterModel | aFilterModel text: substring; yourself ]
]

{ #category : 'accessing' }
ElixirNameSubstringFilter >> filterValueString [
	^ substring
]

{ #category : 'matching' }
ElixirNameSubstringFilter >> matches: anEntry [
	^ (anEntry attributeAt: #name) asString asLowercase
		includesSubstring: substring asLowercase
]

{ #category : 'accessing' }
ElixirNameSubstringFilter >> substring [
	^ substring
]

{ #category : 'accessing' }
ElixirNameSubstringFilter >> substring: aString [
	substring := aString
]
