Class {
	#name : 'ElixirFunctionsFilter',
	#superclass : 'GtSearchFilter',
	#category : 'Gt4beam-Filters',
	#package : 'Gt4beam',
	#tag : 'Filters'
}

{ #category : 'descriptors' }
ElixirFunctionsFilter class >> filterDescriptors2For: aCoder into: aCollection [
	(self filterDescriptor2For: aCoder)
		ifNotNil: [ :aDescriptor | aCollection add: aDescriptor ]
]

{ #category : 'comparing' }
ElixirFunctionsFilter >> = anObject [
	"Value-aware (stock GtSearchFilter compares class only) so a changed value re-applies."
	^ self class = anObject class and: [ self filterValueString = anObject filterValueString ]
]

{ #category : 'matching' }
ElixirFunctionsFilter >> entryKind: anEntry [
	"Normalised kind, '#' stripped: the bridge sends it as 'def'/'type'
	 (ByteString) or #def/#type (BeamAtomObject) depending on the path."
	^ (anEntry attributeAt: #kind)
		ifNil: [ '' ]
		ifNotNil: [ :k | k asString copyWithout: $# ]
]

{ #category : 'comparing' }
ElixirFunctionsFilter >> hash [
	^ self class hash bitXor: self filterValueString hash
]

{ #category : 'highlighting' }
ElixirFunctionsFilter >> highlightRangesIn: aString [
	"Source ranges I want highlighted. None by default; substring filters override."
	^ #()
]

{ #category : 'matching' }
ElixirFunctionsFilter >> isType: anEntry [
	^ #('type' 'opaque' 'typep') includes: (self entryKind: anEntry)
]

{ #category : 'matching' }
ElixirFunctionsFilter >> matches: anEntry [
	^ true
]

{ #category : 'highlighting' }
ElixirFunctionsFilter >> rangesOf: aSubstring in: aString [
	"Case-insensitive, agreeing with the filters' matches:. Scans
	 lowered copies; the ranges index the original string."
	| ranges idx lowered target |
	(aSubstring isNil or: [ aSubstring isEmpty ]) ifTrue: [ ^ #() ].
	lowered := aSubstring asLowercase.
	target := aString asLowercase.
	ranges := OrderedCollection new.
	idx := target indexOfSubCollection: lowered startingAt: 1.
	[ idx > 0 ] whileTrue: [
		ranges add: (idx to: idx + lowered size - 1).
		idx := target indexOfSubCollection: lowered startingAt: idx + 1 ].
	^ ranges
]
