"
I name the namespace range the Functions tab lists: the module itself
(default) or one of its ancestors, each joined by its imports.
"
Class {
	#name : 'ElixirFunctionsUpToFilter',
	#superclass : 'ElixirFunctionsFilter',
	#instVars : [
		'upTo'
	],
	#category : 'Gt4beam-Filters',
	#package : 'Gt4beam',
	#tag : 'Filters'
}

{ #category : 'descriptors' }
ElixirFunctionsUpToFilter class >> filterDescriptor2For: aStreamingModel [
	"Module first and selected, ancestors nearest first."
	| coder |
	coder := aStreamingModel moduleCoder.
	^ GtFilterShortListModel new
		creator: [ :item | self forModule: item itemValue ];
		items: [ (Array with: coder moduleName) , coder existingNamespaceAncestors ];
		selectedItem: coder moduleName;
		displayAllItems;
		name: 'Functions up to';
		order: 5;
		beDefault;
		yourself
]

{ #category : 'instance creation' }
ElixirFunctionsUpToFilter class >> forModule: aString [
	^ self new upTo: aString
]

{ #category : 'descriptors' }
ElixirFunctionsUpToFilter >> filterDescriptor2For: aStreamingModel [
	^ (super filterDescriptor2For: aStreamingModel)
		ifNotNil: [ :aFilterModel | aFilterModel selectedItem: upTo; yourself ]
]

{ #category : 'accessing' }
ElixirFunctionsUpToFilter >> filterValueString [
	^ upTo
]

{ #category : 'matching' }
ElixirFunctionsUpToFilter >> matches: anEntry [
	^ true
]

{ #category : 'accessing' }
ElixirFunctionsUpToFilter >> upTo [
	^ upTo
]

{ #category : 'accessing' }
ElixirFunctionsUpToFilter >> upTo: aString [
	upTo := aString
]
