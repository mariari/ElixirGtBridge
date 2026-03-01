Class {
	#name : 'BeamAtomObject',
	#superclass : 'Object',
	#instVars : [
		'symbol'
	],
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'as yet unclassified' }
BeamAtomObject class >> new: aSymbol [
	^ self new symbol: aSymbol
]

{ #category : 'comparing' }
BeamAtomObject >> = aSymbol [
	"I should probably do this better"

	self class == aSymbol class ifFalse: [ ^ false ].
	^ self symbol = aSymbol symbol
]

{ #category : 'as yet unclassified' }
BeamAtomObject >> determinePID [
	^ self evaluateAndWait: (self resolve , '|> Process.whereis()')
]

{ #category : 'as yet unclassified' }
BeamAtomObject >> evaluateAndWait: aString [
	"I'm unsure how this works when we have multiple beam instances... Since this isn't related to any personal data"

	^ BeamLinkApplication uniqueInstance newCommandFactory
		<< aString;
		sendAndWait
]

{ #category : 'views' }
BeamAtomObject >> gtModuleDocsView: aView [
	<gtView>
	| sections page |
	self isModuleAtom ifFalse: [ ^ aView empty ].
	sections := self evaluateAndWait:
		'GtBridge.Documentation.to_sections('
		, 'GtBridge.Documentation.for_module('
		, self resolve , '))'.
	sections isString ifFalse: [ ^ aView empty ].
	page := LePage named: self symbol.
	LeDatabase new addPage: page.
	(sections splitOn: '__SECTION__') do: [ :s |
		s trimBoth isEmpty ifFalse: [
			page addSnippet: (LeTextSnippet string: s trimBoth) ] ].
	^ aView explicit
		title: 'Documentation';
		priority: 3;
		stencil: [ page asPreviewElement vMatchParent ]
]

{ #category : 'views' }
BeamAtomObject >> gtPIDView: aView [
	<gtView>
	| pid |
	pid := self determinePID.
	pid ifNil: [ ^ aView empty ].
	^ aView composite
		title: 'PID View';
		priority: 2;
		views: pid gtViewsInCurrentContext
]

{ #category : 'comparing' }
BeamAtomObject >> hash [
	^ self symbol hash hashMultiply
]

{ #category : 'testing' }
BeamAtomObject >> isModuleAtom [
	^ symbol notEmpty and: [ symbol first isUppercase ]
]

{ #category : 'as yet unclassified' }
BeamAtomObject >> printOn: aStream [
	self symbol printOn: aStream
]

{ #category : 'elixir - resolution' }
BeamAtomObject >> resolve [
	^ (symbol at: 1) = (symbol at: 1) asUppercase
		ifTrue: [ symbol ]
		ifFalse: [ ':' , symbol ]
]

{ #category : 'accessing' }
BeamAtomObject >> symbol [
	^ symbol
]

{ #category : 'accessing' }
BeamAtomObject >> symbol: anObject [
	symbol := anObject
]
