"
I exercise `BeamEventStreamReader` parsing + dispatch in isolation,
without the HTTP layer.  Each example feeds a synthetic input through
the same paths that the live SSE loop uses, so a regression in the
parsing or routing surface fails here even when the full bridge is
not running.

The full /EVENTS round-trip is a bridge-integration concern and lives
in its own topic alongside `BeamLinkApplication` connection lifecycle.
"
Class {
	#name : 'BeamEventStreamReaderExamples',
	#superclass : 'Object',
	#category : 'Gt4beam-Examples',
	#package : 'Gt4beam',
	#tag : 'Examples'
}

{ #category : 'private' }
BeamEventStreamReaderExamples >> captureRecompiledOn: anAnnouncer [
	"I subscribe to `anAnnouncer`, return `{ subscriber. hits }`.  Caller
	 unsubscribes with `anAnnouncer unsubscribe: subscriber` when done."

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
BeamEventStreamReaderExamples >> dispatchOfRecompiledKindFiresPerModuleAndDefault [
	"I verify that feeding a `kind: 'recompiled'` dict to `dispatch:`
	 fires `BeamModuleRecompiled` on both the per-module announcer and
	 the default singleton."

	<gtExample>
	| reader perModule defaultPair payload |
	reader := BeamEventStreamReader new.
	perModule := self captureRecompiledOn: (BeamEventAnnouncer for: 'GtBridge.Serializer').
	defaultPair := self captureRecompiledOn: BeamEventAnnouncer default.

	payload := Dictionary new
		at: 'kind' put: 'recompiled';
		at: 'mod' put: 'GtBridge.Serializer';
		at: 'source_hash' put: 12345;
		yourself.
	reader dispatch: payload.

	[
		self assert: perModule value asArray equals: #('GtBridge.Serializer').
		self assert: defaultPair value asArray equals: #('GtBridge.Serializer') ] ensure: [
		(BeamEventAnnouncer for: 'GtBridge.Serializer') unsubscribe: perModule key.
		BeamEventAnnouncer default unsubscribe: defaultPair key ].

	^ reader
]

{ #category : 'examples' }
BeamEventStreamReaderExamples >> dispatchIgnoresUnknownKind [
	"I verify that an unknown `kind` is silently dropped — no DNU,
	 no announcement.  Forward-compat for new event kinds added by
	 downstream topics."

	<gtExample>
	| reader pair payload |
	reader := BeamEventStreamReader new.
	pair := self captureRecompiledOn: BeamEventAnnouncer default.

	payload := Dictionary new
		at: 'kind' put: 'something_new';
		at: 'mod' put: 'X';
		yourself.
	reader dispatch: payload.

	[ self assert: pair value isEmpty ] ensure: [
		BeamEventAnnouncer default unsubscribe: pair key ].

	^ reader
]

{ #category : 'examples' }
BeamEventStreamReaderExamples >> handleLineParsesDataFrame [
	"I verify `handleLine:` extracts the JSON payload from a `data:`
	 SSE frame and dispatches it."

	<gtExample>
	| reader pair |
	reader := BeamEventStreamReader new.
	pair := self captureRecompiledOn: BeamEventAnnouncer default.

	reader handleLine: 'data: {"kind":"recompiled","mod":"Foo.Bar","source_hash":7}'.

	[ self assert: pair value asArray equals: #('Foo.Bar') ] ensure: [
		BeamEventAnnouncer default unsubscribe: pair key ].

	^ reader
]

{ #category : 'examples' }
BeamEventStreamReaderExamples >> handleLineIgnoresNonDataPrefix [
	"I verify SSE keep-alive comments / blank lines / unrelated headers
	 are ignored."

	<gtExample>
	| reader pair |
	reader := BeamEventStreamReader new.
	pair := self captureRecompiledOn: BeamEventAnnouncer default.

	reader handleLine: ''.
	reader handleLine: ': keep-alive'.
	reader handleLine: 'event: ping'.

	[ self assert: pair value isEmpty ] ensure: [
		BeamEventAnnouncer default unsubscribe: pair key ].

	^ reader
]

{ #category : 'examples' }
BeamEventStreamReaderExamples >> handleLineSwallowsMalformedJson [
	"I verify a malformed JSON payload logs but does not raise — a
	 single bad frame should not tear down the read loop."

	<gtExample>
	| reader pair |
	reader := BeamEventStreamReader new.
	pair := self captureRecompiledOn: BeamEventAnnouncer default.

	reader handleLine: 'data: {not valid json'.

	[ self assert: pair value isEmpty ] ensure: [
		BeamEventAnnouncer default unsubscribe: pair key ].

	^ reader
]

{ #category : 'examples' }
BeamEventStreamReaderExamples >> singletonPerApplication [
	"I verify `for:` returns the same instance for the same application
	 and a different instance for a different application."

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
