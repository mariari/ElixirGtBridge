Class {
	#name : 'ElixirVisibilityFilter',
	#superclass : 'ElixirFunctionsFilter',
	#instVars : [
		'visibility'
	],
	#category : 'Gt4beam-Filters',
	#package : 'Gt4beam',
	#tag : 'Filters'
}

{ #category : 'instance creation' }
ElixirVisibilityFilter class >> forVisibility: aString [
	^ self new visibility: aString
]

{ #category : 'descriptors' }
ElixirVisibilityFilter class >> globalFilterDescriptor2 [
	^ GtFilterShortListModel new
		creator: [ :item | self forVisibility: item itemValue ];
		items: [ #('All' 'Exported' 'Private') ];
		selectedItem: 'All';
		displayAllItems;
		name: 'Visibility';
		order: 25;
		beDefault;
		yourself
]

{ #category : 'descriptors' }
ElixirVisibilityFilter >> filterDescriptor2For: aCoder [
	^ (super filterDescriptor2For: aCoder)
		ifNotNil: [ :aFilterModel | aFilterModel selectedItem: visibility; yourself ]
]

{ #category : 'accessing' }
ElixirVisibilityFilter >> filterValueString [
	^ visibility
]

{ #category : 'matching' }
ElixirVisibilityFilter >> matches: anEntry [
	"The p-suffixed kinds are the module-private ones."
	| isPrivate |
	visibility = 'All' ifTrue: [ ^ true ].
	isPrivate := #('defp' 'defmacrop' 'typep') includes: (self entryKind: anEntry).
	^ visibility = 'Private' ifTrue: [ isPrivate ] ifFalse: [ isPrivate not ]
]

{ #category : 'accessing' }
ElixirVisibilityFilter >> visibility: aString [
	visibility := aString
]
