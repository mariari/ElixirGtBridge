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
	analysis := ElixirSystemAnalysis
		onApplication: self runningApplication
		gitRepository: self gitRepository.
	self assert: analysis hasApplication.
	self assert: analysis hasGitRepository.
	^ analysis
]

{ #category : 'accessing' }
ElixirSystemAnalysisExamples >> analysisHasLoadedApplications [
	<gtExample>
	| analysis |
	analysis := self analysis.
	self assert: analysis loadedApplicationRecords isNotEmpty.
	^ analysis loadedApplicationRecords
]

{ #category : 'examples - views' }
ElixirSystemAnalysisExamples >> applicationsView [
	<gtExample>
	| view |
	view := self analysis gtApplicationsFor: GtPhlowEmptyView new.
	self assert: view notNil.
	^ view
]

{ #category : 'examples - views' }
ElixirSystemAnalysisExamples >> dashboardView [
	<gtExample>
	| view |
	view := self analysis gtDashboardFor: GtPhlowEmptyView new.
	self assert: view notNil.
	^ view
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
ElixirSystemAnalysisExamples >> gitRepository [
	<gtExample>
	| repository |
	repository := GtGitRepository forRepoNamed: 'gt4beam'.
	self assert: repository isNotNil.
	^ repository
]

{ #category : 'examples - views' }
ElixirSystemAnalysisExamples >> mnesiaTablesView [
	<gtExample>
	| view |
	view := self analysis gtMnesiaTablesFor: GtPhlowEmptyView new.
	self assert: view notNil.
	^ view
]

{ #category : 'examples - views' }
ElixirSystemAnalysisExamples >> overviewView [
	<gtExample>
	| view |
	view := self analysis gtOverviewFor: GtPhlowEmptyView new.
	self assert: view notNil.
	^ view
]

{ #category : 'examples - views' }
ElixirSystemAnalysisExamples >> problemsView [
	<gtExample>
	| view |
	view := self analysis gtProblemsFor: GtPhlowEmptyView new.
	self assert: view notNil.
	^ view
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
