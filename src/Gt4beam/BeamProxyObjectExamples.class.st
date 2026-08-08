Class {
	#name : 'BeamProxyObjectExamples',
	#superclass : 'Object',
	#category : 'Gt4beam-Examples',
	#package : 'Gt4beam',
	#tag : 'Examples'
}

{ #category : 'examples' }
BeamProxyObjectExamples >> documentationObjectClassSelection [
	<gtExample>
	| proxy |
	proxy := BeamProxyObject elixirClass: 'GtBridge.Documentation'.
	self assert: proxy class equals: BeamDocumentationObject.
	^ proxy
]

{ #category : 'examples' }
BeamProxyObjectExamples >> fetchAnswersBridgeData [
	"I fetch plain bridge data in one round trip: an atom arrives as a
	 BeamAtomObject, a pid as a live BeamPIDObject."
	<gtExample>
	| application fetched |
	application := Gt4beamSessionLifecycleExamples new application.
	fetched := BeamProxyObject
		fetch: '%{name: :alice, pid: self()}'
		through: application.
	self assert: (fetched at: 'name') class equals: BeamAtomObject.
	self assert: (fetched at: 'name') symbol equals: #alice.
	self assert: (fetched at: 'pid') class equals: BeamPIDObject.
	^ fetched
]

{ #category : 'examples' }
BeamProxyObjectExamples >> fetchAnswersTheErrorWhenTheNodeRefuses [
	"I answer the node's error rather than nil, so the caller keeps why."
	<gtExample>
	| application refused |
	application := Gt4beamSessionLifecycleExamples new application.
	refused := BeamProxyObject fetch: 'raise "boom"' through: application.
	self assert: refused isError.
	self assert: refused messageText equals: '** (RuntimeError) boom'.
	^ refused
]

{ #category : 'examples' }
BeamProxyObjectExamples >> functionLinesHandlesRemoteErrors [
	<gtExample>
	<noTest>
	| application proxy |
	application := BeamLinkApplication start.
	self assert: application isRunning.
	proxy := BeamBridgeEvalError new.
	proxy rawData: Dictionary new.
	proxy application: application.
	proxy elixirClass: 'GtBridge.Eval.Error'.
	proxy elixirVar: 1.
	self assert: proxy functionLines isNil.
	^ proxy
]

{ #category : 'examples' }
BeamProxyObjectExamples >> plainProxyHasNoFunctionLines [
	<gtExample>
	| proxy |
	proxy := BeamProxyObject new.
	self assert: proxy functionLines isNil.
	^ proxy
]
