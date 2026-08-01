Class {
	#name : 'ElixirSystemAnalysisExamples',
	#superclass : 'Object',
	#category : 'Gt4beam-Examples',
	#package : 'Gt4beam',
	#tag : 'Examples'
}

{ #category : 'accessing' }
ElixirSystemAnalysisExamples >> analysis [
	<gtExample>
	| analysis |
	analysis := ElixirSystemAnalysis onApplication: self runningApplication.
	self assert: analysis hasApplication.
	^ analysis
]

{ #category : 'accessing' }
ElixirSystemAnalysisExamples >> firstApplication [
	<gtExample>
	| application |
	application := self analysis applications first.
	self assert: application name isNotNil.
	^ application
]

{ #category : 'accessing' }
ElixirSystemAnalysisExamples >> runningApplication [
	<gtExample>
	| application |
	application := BeamLinkApplication allInstances
		detect: [ :each | 
			((each instVarNamed: 'settings') isNotNil)
				and: [ each isRunning ] ]
		ifNone: [ BeamLinkApplication start ].
	self assert: application isNotNil.
	self assert: application isRunning.
	^ application
]
