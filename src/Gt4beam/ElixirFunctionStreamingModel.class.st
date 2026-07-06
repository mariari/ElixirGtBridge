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
	coder list: self.
	^ coder
]

{ #category : 'streaming' }
ElixirFunctionStreamingModel >> newItemsStream [
	"additionalFilters (not compositeFilter): the null main filter isn't a
	 predicate, and entries keep all_functions/1 order via select:."
	^ (moduleCoder functionEntries select: [ :e |
		self additionalFilters allSatisfy: [ :f | f matches: e ] ]) asAsyncStream
]

{ #category : 'announcements' }
ElixirFunctionStreamingModel >> onModuleSourceCodeChanged: anAnnouncement [
	"I refresh whenever my coder publishes its translated
	 GtCoderSourceCodeChanged.  The coder has already populated its
	 cache from the BeamModuleRecompiled payload by the time I run, so
	 `refreshStream` reads cached function entries — no bridge call."
	self refreshStream
]

{ #category : 'streaming' }
ElixirFunctionStreamingModel >> refreshItemsStreamDueTo: aReason [
	super refreshItemsStreamDueTo: aReason.
	self restyleHighlightCoders
]

{ #category : 'as yet unclassified' }
ElixirFunctionStreamingModel >> refreshStream [
	"Drops cached entries whose key isn't in the fresh set —
	 recovers from a transient `nil/nil` entry captured before
	 the source cache primed."
	| freshKeys |
	freshKeys := Set new.
	moduleCoder functionEntries do: [ :entry |
		| key cached |
		key := self newCoderCacheKeyFor: entry.
		freshKeys add: key.
		cached := mutex critical: [ coders at: key ifAbsent: [ nil ] ].
		cached ifNotNil: [ cached refreshFromEntry: entry ] ].
	mutex critical: [
		coders keys copy do: [ :k |
			(freshKeys includes: k) ifFalse: [ coders removeKey: k ] ] ].
	self refreshItemsStreamDueTo: 'functions reordered'
]

{ #category : 'streaming' }
ElixirFunctionStreamingModel >> restyleHighlightCoders [
	"Rebuild each cached coder's addOns so the <gtAstCoderAddOns:> highlight styler re-reads
	 the active substrings and re-underlines (or clears) after a filter change."

	(mutex critical: [ coders values asArray ])
		do: [ :coder | coder requestUpdateAddOns ]
]
