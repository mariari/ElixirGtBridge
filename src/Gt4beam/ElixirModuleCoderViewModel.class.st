Class {
	#name : 'ElixirModuleCoderViewModel',
	#superclass : 'GtSingleCoderViewModel',
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'as yet unclassified' }
ElixirModuleCoderViewModel >> coder [
	^ self coderModel
]

{ #category : 'accessing' }
ElixirModuleCoderViewModel >> elementClass [
	^ ElixirModuleCoderElement
]

{ #category : 'as yet unclassified' }
ElixirModuleCoderViewModel >> moduleName [
	^ self coder moduleName
]
