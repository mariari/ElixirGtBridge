Class {
	#name : 'ElixirFunctionStreamingModel',
	#superclass : 'GtFilteredCodersModel',
	#instVars : [
		'moduleCoder',
		'lastRange'
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
	 GtCoderSourceCodeChanged locally.  Entries reach me through
	 rangeEntries, reading each range coder's own entries — no
	 global subscription of my own, no second bridge call.

	 If reassigned to a different coder, drop the prior subscription
	 first so I don't leak."
	moduleCoder ifNotNil: [ moduleCoder announcer unsubscribe: self ].
	moduleCoder := anElixirModuleCoder.
	moduleCoder announcer weak
		when: GtCoderSourceCodeChanged
		send: #onModuleSourceCodeChanged:
		to: self
]

{ #category : 'range' }
ElixirFunctionStreamingModel >> upToModuleName [
	"The filter's choice, or my own module when no filter is active."
	^ (self additionalFilters
		detect: [ :f | f isKindOf: ElixirFunctionsUpToFilter ]
		ifNone: [ nil ])
		ifNil: [ moduleCoder moduleName ]
		ifNotNil: [ :f | f upTo ]
]

{ #category : 'range' }
ElixirFunctionStreamingModel >> rangeCoders [
	"Own coder first. Each coder points back at me so substring
	 highlighting finds the active filters through any row."
	| coders |
	coders := moduleCoder coderRangeUpTo: self upToModuleName.
	coders do: [ :each | each functionStreamingModel: self ].
	self announceRange: (coders collect: [ :each | each moduleName ]) asArray.
	^ coders
]

{ #category : 'range' }
ElixirFunctionStreamingModel >> rangeEntries [
	^ Array streamContents: [ :s |
		self rangeCoders do: [ :coder |
			coder functionEntries do: [ :entry |
				s nextPut: (ElixirRangeEntry entry: entry moduleCoder: coder) ] ] ]
]

{ #category : 'range' }
ElixirFunctionStreamingModel >> announceRange: anArray [
	lastRange = anArray ifTrue: [ ^ self ].
	lastRange := anArray.
	moduleCoder announce: (ElixirFunctionRangeChanged modules: anArray)
]

{ #category : 'streaming' }
ElixirFunctionStreamingModel >> newCoderCacheKeyFor: anEntry [
	"Module-qualified: the same name/arity can live in two modules of a range."
	^ (anEntry attributeAt: #module) asString, '.',
		(anEntry attributeAt: #name) asString, '/', (anEntry attributeAt: #arity) asString
]

{ #category : 'streaming' }
ElixirFunctionStreamingModel >> newCoderFor: anEntry [
	"A foreign entry's coder belongs to its own module coder, shows the
	 crumb, and gets no list: Move only makes sense within one module."
	| coder foreign |
	foreign := anEntry isForeignTo: moduleCoder.
	coder := ElixirFunctionCoder forEntry: anEntry moduleCoder: anEntry moduleCoder.
	coder selfObject: moduleCoder selfObject.
	coder showsModuleInHeader: foreign.
	foreign ifFalse: [ coder list: self ].
	^ coder
]

{ #category : 'streaming' }
ElixirFunctionStreamingModel >> newItemsStream [
	"additionalFilters (not compositeFilter): the null main filter isn't a
	 predicate, and entries keep all_functions/1 order via select:."
	^ (self rangeEntries select: [ :e |
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
	"Drops cached coders whose key isn't in the fresh range."
	| freshKeys |
	freshKeys := Set new.
	self rangeEntries do: [ :entry |
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
