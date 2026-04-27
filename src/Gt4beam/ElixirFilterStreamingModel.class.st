Class {
	#name : 'ElixirFilterStreamingModel',
	#superclass : 'GtStreamingCodersModel',
	#instVars : [
		'items',
		'application'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam'
}

{ #category : 'accessing' }
ElixirFilterStreamingModel >> items: aCollection application: anApp [
	items := aCollection.
	application := anApp
]

{ #category : 'accessing' }
ElixirFilterStreamingModel >> newCoderCacheKeyFor: anEntry [
	^ (anEntry attributeAt: #module) asString, '.',
	  (anEntry attributeAt: #name) asString, '/',
	  (anEntry attributeAt: #arity) asString
]

{ #category : 'accessing' }
ElixirFilterStreamingModel >> newCoderFor: anEntry [
	"I create an ElixirFunctionCoder for the entry by building
	 a lightweight module coder for its module. The coder shows
	 a clickable Module > function/arity header so the reader
	 knows which module each filter result comes from and can
	 spawn module / function docs directly."
	| modName mc sourcePath |
	modName := (anEntry attributeAt: #module) asString.
	sourcePath := [ application evaluateAndWait:
		'GtBridge.Resolve.source_file(', modName, ')' ]
		on: Error do: [ nil ].
	mc := ElixirModuleCoder new
		moduleName: modName;
		application: application.
	sourcePath ifNotNil: [ mc sourcePath: sourcePath ].
	^ (ElixirFunctionCoder forEntry: anEntry moduleCoder: mc)
		showsModuleInHeader: true;
		yourself
]

{ #category : 'accessing' }
ElixirFilterStreamingModel >> newItemsStream [
	^ items asAsyncStream
]
