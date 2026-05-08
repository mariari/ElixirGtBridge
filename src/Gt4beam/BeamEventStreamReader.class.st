"
I am the GT-side reader of the bridge's `/EVENTS` Server-Sent
Events stream.  I open one long-lived HTTP connection per
`BeamLinkApplication`, read `data:` frames as they arrive, and
fire matching announcements on `BeamEventAnnouncer default`.

I am the SOLE publisher into `BeamEventAnnouncer`.  No UI surface
mints events from observed HTTP responses; everything flows through
`GtBridge.CodeMonitor` → `GtBridge.Events.broadcast` →
`/EVENTS` → me → `BeamEventAnnouncer`.

Lifecycle:
- `BeamEventStreamReader for: anApp` returns a singleton per app.
- `start` opens the connection in a background process.
- `stop` closes the connection.
- The reader auto-reconnects on stream end (with a small backoff)
  while the application is alive.
"
Class {
	#name : 'BeamEventStreamReader',
	#superclass : 'Object',
	#instVars : [
		'application',
		'client',
		'readerProcess',
		'running'
	],
	#classVars : [
		'Readers'
	],
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}

{ #category : 'instance creation' }
BeamEventStreamReader class >> for: anApp [
	"I return the singleton reader for this application, creating it on
	 first request."

	Readers ifNil: [ Readers := IdentityDictionary new ].
	^ Readers
		at: anApp
		ifAbsentPut: [ self new application: anApp; yourself ]
]

{ #category : 'accessing' }
BeamEventStreamReader >> application: anApp [
	application := anApp
]

{ #category : 'accessing' }
BeamEventStreamReader >> isRunning [
	^ running == true
		and: [ readerProcess notNil and: [ readerProcess isTerminated not ] ]
]

{ #category : 'lifecycle' }
BeamEventStreamReader >> start [
	"I spawn the reader process if not already running.  Idempotent."

	self isRunning ifTrue: [ ^ self ].
	running := true.
	readerProcess := [ self readLoop ] forkAt: Processor userBackgroundPriority
		named: 'Beam event stream reader'
]

{ #category : 'lifecycle' }
BeamEventStreamReader >> stop [
	running := false.
	client ifNotNil: [
		[ client close ] on: Error do: [ ].
		client := nil ].
	readerProcess ifNotNil: [
		[ readerProcess terminate ] on: Error do: [ ].
		readerProcess := nil ]
]

{ #category : 'private' }
BeamEventStreamReader >> readLoop [
	"I open the SSE connection and dispatch each frame.  On stream end
	 or transient error I back off and reconnect while running."

	[ running ] whileTrue: [
		[ self openAndConsume ] on: Error do: [ :e | self logError: e ].
		running ifTrue: [ (Delay forSeconds: 1) wait ] ]
]

{ #category : 'private' }
BeamEventStreamReader >> openAndConsume [
	| serverAddress url |
	serverAddress := application settings serverSocketAddress.
	url := 'http://' , serverAddress ipOrName , ':'
		, serverAddress port asString , '/EVENTS'.
	client := ZnClient new
		url: url;
		method: #GET;
		streaming: true;
		getConnectionAndExecute.
	client connection
		liveReadLoopDo: [ :line | self handleLine: line ]
]

{ #category : 'private' }
BeamEventStreamReader >> handleLine: aLine [
	| trimmed payload event |
	trimmed := aLine trimBoth.
	(trimmed beginsWith: 'data:') ifFalse: [ ^ self ].
	payload := (trimmed allButFirst: 5) trimBoth.
	event := [ STONJSON fromString: payload ] on: Error do: [ :e |
		self logError: e.
		^ self ].
	self dispatch: event
]

{ #category : 'private' }
BeamEventStreamReader >> dispatch: aDict [
	"I route a decoded SSE frame to the matching announcer call.
	 Each event-introducing topic extends me with its own kind."

	| kind mod |
	kind := aDict at: 'kind' ifAbsent: [ ^ self ].
	mod := aDict at: 'mod' ifAbsent: [ nil ].
	kind = 'recompiled' ifTrue: [
		^ BeamEventAnnouncer announceRecompiledFrom: (Dictionary new
			at: #mod put: mod;
			at: #source_hash put: (aDict at: 'source_hash' ifAbsent: [ nil ]);
			yourself) ].
	kind = 'source_removed' ifTrue: [
		mod ifNil: [ ^ self ].
		^ BeamEventAnnouncer announceSourceRemoved: mod ]
]

{ #category : 'private' }
BeamEventStreamReader >> logError: anException [
	Transcript
		show: 'BeamEventStreamReader error: ';
		show: anException printString;
		cr
]
