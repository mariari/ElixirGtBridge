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
	| ranges idx |
	(aSubstring isNil or: [ aSubstring isEmpty ]) ifTrue: [ ^ #() ].
	ranges := OrderedCollection new.
	idx := aString indexOfSubCollection: aSubstring startingAt: 1.
	[ idx > 0 ] whileTrue: [
		ranges add: (idx to: idx + aSubstring size - 1).
		idx := aString indexOfSubCollection: aSubstring startingAt: idx + 1 ].
	^ ranges
]
