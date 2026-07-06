Class {
	#name : 'ElixirKindFilter',
	#superclass : 'ElixirFunctionsFilter',
	#instVars : [
		'kind'
	],
	#category : 'Gt4beam-Filters',
	#package : 'Gt4beam',
	#tag : 'Filters'
}

{ #category : 'instance creation' }
ElixirKindFilter class >> forKind: aString [
	^ self new kind: aString
]

{ #category : 'descriptors' }
ElixirKindFilter class >> globalFilterDescriptor2 [
	^ GtFilterShortListModel new
		creator: [ :item | self forKind: item itemValue ];
		items: [ #('All' 'Functions' 'Types') ];
		selectedItem: 'All';
		displayAllItems;
		name: 'Kind';
		order: 20;
		beDefault;
		yourself
]

{ #category : 'descriptors' }
ElixirKindFilter >> filterDescriptor2For: aCoder [
	^ (super filterDescriptor2For: aCoder)
		ifNotNil: [ :aFilterModel | aFilterModel selectedItem: kind; yourself ]
]

{ #category : 'accessing' }
ElixirKindFilter >> filterValueString [
	^ kind
]

{ #category : 'accessing' }
ElixirKindFilter >> kind [
	^ kind
]

{ #category : 'accessing' }
ElixirKindFilter >> kind: aString [
	kind := aString
]

{ #category : 'matching' }
ElixirKindFilter >> matches: anEntry [
	kind = 'Types' ifTrue: [ ^ self isType: anEntry ].
	kind = 'Functions' ifTrue: [ ^ (self isType: anEntry) not ].
	^ true
]
