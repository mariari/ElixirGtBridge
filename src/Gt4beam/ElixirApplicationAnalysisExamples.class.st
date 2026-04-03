Class {
	#name : 'ElixirApplicationAnalysisExamples',
	#superclass : 'Object',
	#category : 'Gt4beam-Examples',
	#package : 'Gt4beam',
	#tag : 'Examples'
}

{ #category : 'accessing' }
ElixirApplicationAnalysisExamples >> application [
	<gtExample>
	| application |
	application := ElixirSystemAnalysisExamples new firstApplication.
	self assert: application hasTuple.
	^ application
]

{ #category : 'examples' }
ElixirApplicationAnalysisExamples >> applicationHasModules [
	<gtExample>
	| application modules |
	application := self application.
	modules := application modules.
	self assert: modules isNotNil.
	self assert: modules class name equals: #BeamListObject.
	^ modules
]

{ #category : 'accessing' }
ElixirApplicationAnalysisExamples >> applicationHasNameVersionAndDescription [
	<gtExample>
	| application |
	application := self application.
	self assert: application name isNotNil.
	self assert: application version isNotNil.
	self assert: application description isNotNil.
	^ application
]

{ #category : 'examples' }
ElixirApplicationAnalysisExamples >> applicationOverviewIncludesModules [
	<gtExample>
	| application |
	application := self application.
	self assert: application hasModules.
	^ application
]

