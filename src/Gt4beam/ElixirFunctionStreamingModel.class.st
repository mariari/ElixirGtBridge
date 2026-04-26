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
	"I create an ElixirFunctionCoder for a function entry, 
	 propagating selfObject so single-arity functions can Run with it."
	| coder |
	coder := ElixirFunctionCoder forEntry: anEntry moduleCoder: moduleCoder.
	coder selfObject: moduleCoder selfObject.
	^ coder
]

{ #category : 'streaming' }
ElixirFunctionStreamingModel >> newItemsStream [
	"I return function entries as an async stream in the order
	 GtBridge.Analysis.all_functions/1 emits them.  The BEAM-side
	 already groups default-arg arity siblings (start: 0) above
	 their AST counterpart and parks orphan macro-generated entries
	 at the end, so re-sorting by start would just lump every
	 start: 0 entry at the top."
	^ moduleCoder functionEntries asList asAsyncStream
]

{ #category : 'as yet unclassified' }
ElixirFunctionStreamingModel >> refreshStream [
	"I re-query function entries from the module coder and refresh my
	 stream — but I keep the existing coder cache.  Saving one function
	 announces a source change which lands here; clearing the cache
	 would force every coder to be recreated and lose the user's
	 expansion state.  The saved coder's source is already refreshed
	 in-place by ElixirFunctionCoder>>saveFunction, and unchanged
	 functions don't need new coders."
	self refreshItemsStreamDueTo: 'functions reordered'
]
