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
ElixirApplicationAnalysisExamples >> applicationHasModules [
	<gtExample>
	| application modules |
	application := self application.
	modules := application modules.
	self assert: modules isNotNil.
	self assert: modules class name equals: #BeamListObject.
	^ modules
]

{ #category : 'examples' }
ElixirApplicationAnalysisExamples >> applicationOverviewIncludesModules [
	<gtExample>
	| application |
	application := self application.
	self assert: application hasModules.
	^ application
]

{ #category : 'examples' }
ElixirApplicationAnalysisExamples >> moduleTreeRoots [
	<gtExample>
	| roots |
	roots := self application moduleTreeRoots.
	self assert: roots isNotEmpty.
	self assert: (roots first at: #label) isNotNil.
	^ roots
]

{ #category : 'examples - views' }
ElixirApplicationAnalysisExamples >> dependencyGraphView [
	<gtExample>
	| view |
	view := self application gtDependencyGraphFor: GtPhlowEmptyView new.
	self assert: view notNil.
	^ view
]

{ #category : 'examples - views' }
ElixirApplicationAnalysisExamples >> moduleTreeView [
	<gtExample>
	| view |
	view := self application gtModuleTreeFor: GtPhlowEmptyView new.
	self assert: view notNil.
	^ view
]

{ #category : 'examples - views' }
ElixirApplicationAnalysisExamples >> overviewView [
	<gtExample>
	| view |
	view := self application gtOverviewFor: GtPhlowEmptyView new.
	self assert: view notNil.
	^ view
]

{ #category : 'examples - views' }
ElixirApplicationAnalysisExamples >> problemsView [
	<gtExample>
	| view |
	view := self application gtProblemsFor: GtPhlowEmptyView new.
	self assert: view notNil.
	^ view
]

{ #category : 'examples - views' }
ElixirApplicationAnalysisExamples >> reverseDepsView [
	<gtExample>
	| view |
	view := self application gtReverseDepsFor: GtPhlowEmptyView new.
	self assert: view notNil.
	^ view
]
