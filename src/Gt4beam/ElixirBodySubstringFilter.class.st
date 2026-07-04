Class {
	#name : 'ElixirBodySubstringFilter',
	#superclass : 'ElixirFunctionsFilter',
	#instVars : [
		'substring'
	],
	#category : 'Gt4beam-Filters',
	#package : 'Gt4beam',
	#tag : 'Filters'
}

{ #category : 'descriptors' }
ElixirBodySubstringFilter class >> globalFilterDescriptor2 [
	^ GtFilterTextModel new
		creator: [ :value | self substring: value ];
		named: 'Substring';
		order: 10;
		yourself
]

{ #category : 'descriptors' }
ElixirBodySubstringFilter class >> substring: value [
	^ self new substring: value
]

{ #category : 'descriptors' }
ElixirBodySubstringFilter >> filterDescriptor2For: aMethodsCoder [
	^ (super filterDescriptor2For: aMethodsCoder)
		ifNotNil: [ :aFilterModel | 
			aFilterModel
				text: substring;
				yourself ]
]

{ #category : 'accessing' }
ElixirBodySubstringFilter >> filterValueString [
	^ self substring
]

{ #category : 'testing' }
ElixirBodySubstringFilter >> matches: anEntry [
	^ (anEntry attributeAt: #source) includesSubstring: self substring
]

{ #category : 'accessing' }
ElixirBodySubstringFilter >> substring [
	^ substring
]

{ #category : 'accessing' }
ElixirBodySubstringFilter >> substring: anObject [
	substring := anObject
]
