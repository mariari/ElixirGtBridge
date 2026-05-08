"
I exercise `BeamEventStreamReader` parsing + dispatch in isolation.

Examples compose: `freshReader` is the leaf, `dispatchOfRecompiledFires`
proves the dispatch chain end-to-end, and the parsing examples each
extend that verified-working reader with one new property (SSE line
parsing, non-data tolerance, malformed-JSON tolerance, unknown-kind
forward-compat).  Each example returns the reader so the next can
build on it.

The full /EVENTS round-trip lives in its own topic alongside
`BeamLinkApplication` connection lifecycle.
"
Class {
	#name : 'BeamEventStreamReaderExamples',
	#superclass : 'Object',
	#category : 'Gt4beam-Examples',
	#package : 'Gt4beam',
	#tag : 'Examples'
}

{ #category : 'private' }
BeamEventStreamReaderExamples >> recompiledHitsOn: anAnnouncer [
	"I subscribe `anAnnouncer` for BeamModuleRecompiled and return
	 `subscriber -> hits` so callers can assert + unsubscribe."

	| subscriber hits |
	subscriber := Object new.
	hits := OrderedCollection new.
	anAnnouncer
		when: BeamModuleRecompiled
		do: [ :ann | hits add: ann mod ]
		for: subscriber.
	^ subscriber -> hits
]

{ #category : 'examples' }
BeamEventStreamReaderExamples >> freshReader [
	"Building block: a fresh reader instance."

	<gtExample>
	^ BeamEventStreamReader new
]

{ #category : 'examples' }
BeamEventStreamReaderExamples >> dispatchOfRecompiledFires [
	"I verify that feeding a `kind: 'recompiled'` payload to
	 `dispatch:` fires `BeamModuleRecompiled` on both the per-module
	 announcer and the default singleton.  Returns the verified-
	 working reader for the parsing examples to extend."

	<gtExample>
	| reader perModulePair defaultPair payload |
	reader := self freshReader.
	perModulePair := self recompiledHitsOn: (BeamEventAnnouncer for: 'GtBridge.Serializer').
	defaultPair := self recompiledHitsOn: BeamEventAnnouncer default.

	payload := Dictionary new
		at: 'kind' put: 'recompiled';
		at: 'mod' put: 'GtBridge.Serializer';
		at: 'source_hash' put: 12345;
		yourself.
	[ reader dispatch: payload.
		self assert: perModulePair value asArray equals: #('GtBridge.Serializer').
		self assert: defaultPair value asArray equals: #('GtBridge.Serializer') ]
		ensure: [
			(BeamEventAnnouncer for: 'GtBridge.Serializer') unsubscribe: perModulePair key.
			BeamEventAnnouncer default unsubscribe: defaultPair key ].
	^ reader
]

{ #category : 'examples' }
BeamEventStreamReaderExamples >> handleLineParsesData [
	"I extend the verified-dispatch reader with the wire format:
	 `data: <json>` lines should reach the announcer through the
	 same chain `dispatchOfRecompiledFires` already proved."

	<gtExample>
	| reader pair |
	reader := self dispatchOfRecompiledFires.
	pair := self recompiledHitsOn: BeamEventAnnouncer default.
	[ reader handleLine: 'data: {"kind":"recompiled","mod":"Foo.Bar","source_hash":7}'.
		self assert: pair value asArray equals: #('Foo.Bar') ]
		ensure: [ BeamEventAnnouncer default unsubscribe: pair key ].
	^ reader
]

{ #category : 'examples' }
BeamEventStreamReaderExamples >> handleLineIgnoresNonData [
	"I extend the parsing chain with negative cases: SSE keep-alive
	 comments, blank lines, and unrelated headers must drop silently."

	<gtExample>
	| reader pair |
	reader := self handleLineParsesData.
	pair := self recompiledHitsOn: BeamEventAnnouncer default.
	[ reader handleLine: ''.
		reader handleLine: ': keep-alive'.
		reader handleLine: 'event: ping'.
		self assert: pair value isEmpty ]
		ensure: [ BeamEventAnnouncer default unsubscribe: pair key ].
	^ reader
]

{ #category : 'examples' }
BeamEventStreamReaderExamples >> handleLineSwallowsMalformedJson [
	"I extend the chain with bad-JSON tolerance — a single bad frame
	 must log without raising so the read loop survives."

	<gtExample>
	| reader pair |
	reader := self handleLineIgnoresNonData.
	pair := self recompiledHitsOn: BeamEventAnnouncer default.
	[ reader handleLine: 'data: {not valid json'.
		self assert: pair value isEmpty ]
		ensure: [ BeamEventAnnouncer default unsubscribe: pair key ].
	^ reader
]

{ #category : 'examples' }
BeamEventStreamReaderExamples >> dispatchIgnoresUnknownKind [
	"I extend the chain with forward-compat: unknown event kinds
	 must drop silently so future BEAM-side broadcasts don't crash
	 older readers."

	<gtExample>
	| reader pair |
	reader := self handleLineSwallowsMalformedJson.
	pair := self recompiledHitsOn: BeamEventAnnouncer default.
	[ reader dispatch: (Dictionary new
			at: 'kind' put: 'something_new';
			at: 'mod' put: 'X';
			yourself).
		self assert: pair value isEmpty ]
		ensure: [ BeamEventAnnouncer default unsubscribe: pair key ].
	^ reader
]

{ #category : 'examples' }
BeamEventStreamReaderExamples >> singletonPerApplication [
	"Standalone — `for: app` returns the same instance per application,
	 distinct across applications."

	<gtExample>
	| appA appB readerA1 readerA2 readerB |
	appA := Object new.
	appB := Object new.
	readerA1 := BeamEventStreamReader for: appA.
	readerA2 := BeamEventStreamReader for: appA.
	readerB := BeamEventStreamReader for: appB.
	self assert: readerA1 == readerA2.
	self deny: readerA1 == readerB.
	^ readerA1
]
