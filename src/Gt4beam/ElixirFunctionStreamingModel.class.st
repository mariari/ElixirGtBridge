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
	"I subscribe (weakly) to the coder's local announcer for
	 GtCoderSourceCodeChanged.  The coder is the single subscriber to
	 the global per-module BeamEventAnnouncer; it primes its
	 functionEntries cache from the announcement payload and republishes
	 GtCoderSourceCodeChanged locally.  I read the freshly cached
	 entries via `moduleCoder functionEntries` — no global subscription
	 of my own, no second bridge call.

	 If reassigned to a different coder, drop the prior subscription
	 first so I don't leak."
	moduleCoder ifNotNil: [ moduleCoder announcer unsubscribe: self ].
	moduleCoder := anElixirModuleCoder.
	moduleCoder announcer weak
		when: GtCoderSourceCodeChanged
		send: #onModuleSourceCodeChanged:
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
	^ moduleCoder functionEntries asAsyncStream
]

{ #category : 'announcements' }
ElixirFunctionStreamingModel >> onModuleSourceCodeChanged: anAnnouncement [
	"I refresh whenever my coder publishes its translated
	 GtCoderSourceCodeChanged.  The coder has already populated its
	 cache from the BeamModuleRecompiled payload by the time I run, so
	 `refreshStream` reads cached function entries — no bridge call."
	self refreshStream
]

{ #category : 'as yet unclassified' }
ElixirFunctionStreamingModel >> refreshStream [
	"I re-query function entries from the module coder and refresh my
	 stream.  I keep the existing coder cache so the user doesn't lose
	 their expansion state, but I push fresh source/line metadata into
	 each cached coder — saves can come from peer paths (a |> expander,
	 a different ElixirModuleCoder for the same module) that don't
	 touch this list's row coders directly."
	moduleCoder functionEntries do: [ :entry |
		| key cached |
		key := self newCoderCacheKeyFor: entry.
		cached := mutex critical: [ coders at: key ifAbsent: [ nil ] ].
		cached ifNotNil: [ cached refreshFromEntry: entry ] ].
	self refreshItemsStreamDueTo: 'functions reordered'
]
