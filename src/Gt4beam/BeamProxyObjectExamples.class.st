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
