Class {
	#name : 'ElixirFunctionStreamingModel',
	#superclass : 'GtFilteredCodersModel',
	#instVars : [
		'moduleCoder'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'instance creation' }
ElixirFunctionStreamingModel class >> forModuleCoder: anElixirModuleCoder [
	^ self new
		moduleCoder: anElixirModuleCoder;
		refreshItemsStreamDueTo: 'initial';
		yourself
]

{ #category : 'accessing' }
ElixirFunctionStreamingModel >> moduleCoder [
	^ moduleCoder
]

{ #category : 'accessing' }
ElixirFunctionStreamingModel >> moduleCoder: anElixirModuleCoder [
	moduleCoder := anElixirModuleCoder.
	moduleCoder weak
		when: GtCoderSourceCodeChanged 
		send: #refreshStream 
		to: self
]

{ #category : 'streaming' }
ElixirFunctionStreamingModel >> newCoderCacheKeyFor: anEntry [
	"I cache by function name + arity."
	^ (anEntry attributeAt: #name) asString, '/', (anEntry attributeAt: #arity) asString
]

{ #category : 'streaming' }
ElixirFunctionStreamingModel >> newCoderFor: anEntry [
	"I create an ElixirFunctionCoder for a function entry."
	^ ElixirFunctionCoder forEntry: anEntry moduleCoder: moduleCoder
]

{ #category : 'streaming' }
ElixirFunctionStreamingModel >> newItemsStream [
	"I return function entries in source file order as an async stream."
	^ (moduleCoder functionEntries asList
		sort: [ :a :b | (a attributeAt: #start) < (b attributeAt: #start) ])
		asAsyncStream
]

{ #category : 'as yet unclassified' }
ElixirFunctionStreamingModel >> refreshStream [
	"I re-query function entries from the module coder and refresh my stream."
	self refreshItemsStreamDueTo: 'functions reordered'.
	coders := Dictionary new
]
