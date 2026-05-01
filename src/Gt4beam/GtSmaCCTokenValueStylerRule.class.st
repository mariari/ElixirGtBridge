Class {
	#name : 'GtSmaCCTokenValueStylerRule',
	#superclass : 'GtSmaCCTokenStylerRule',
	#category : 'Gt4beam',
	#package : 'Gt4beam'
}

{ #category : 'as yet unclassified' }
GtSmaCCTokenValueStylerRule >> initializeForParser: parserClass [
]

{ #category : 'as yet unclassified' }
GtSmaCCTokenValueStylerRule >> shouldApplyToToken: aSmaCCToken [
	^ tokenName = aSmaCCToken source
]
