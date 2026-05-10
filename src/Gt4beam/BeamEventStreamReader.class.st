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
		'KindHandlers',
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

{ #category : 'private' }
BeamEventStreamReader class >> kindHandlers [
	"Map SSE `kind` → instance-side selector that handles the decoded
	 frame.  Adding an event type means dropping a new handler method
	 and an entry here, no change to `dispatch:`."
	^ KindHandlers ifNil: [
		KindHandlers := Dictionary new
			at: 'recompiled' put: #handleRecompiled:;
			at: 'source_written' put: #handleSourceWritten:;
			at: 'compile_failed' put: #handleCompileFailed:;
			at: 'source_removed' put: #handleSourceRemoved:;
			yourself ]
]

{ #category : 'accessing' }
BeamEventStreamReader >> application: anApp [
	application := anApp
]

{ #category : 'private' }
BeamEventStreamReader >> dispatch: aDict [
	| kind handler |
	kind := aDict at: 'kind' ifAbsent: [ ^ self ].
	handler := self class kindHandlers at: kind ifAbsent: [ ^ self ].
	self perform: handler with: aDict
]

{ #category : 'private' }
BeamEventStreamReader >> handleCompileFailed: aDict [
	| mod |
	mod := aDict at: 'mod' ifAbsent: [ ^ self ].
	BeamEventAnnouncer
		announceCompileFailedFor: mod
		application: application
		errors: (aDict at: 'errors' ifAbsent: [ #() ])
		functionHint: nil
		arityHint: nil
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
	[ self dispatch: event ] on: Error do: [ :e | self logError: e ]
]

{ #category : 'private' }
BeamEventStreamReader >> handleRecompiled: aDict [
	BeamEventAnnouncer
		announceRecompiledFrom: (self payloadFrom: aDict keys: #(mod source_hash source functions))
]

{ #category : 'private' }
BeamEventStreamReader >> handleSourceRemoved: aDict [
	| mod |
	mod := aDict at: 'mod' ifAbsent: [ ^ self ].
	BeamEventAnnouncer announceSourceRemoved: mod
]

{ #category : 'private' }
BeamEventStreamReader >> handleSourceWritten: aDict [
	| mod |
	mod := aDict at: 'mod' ifAbsent: [ ^ self ].
	BeamEventAnnouncer
		announceSourceWrittenFor: mod
		fromPayload: (self payloadFrom: aDict keys: #(source_hash source functions))
]

{ #category : 'accessing' }
BeamEventStreamReader >> isRunning [
	^ running == true
		and: [ readerProcess notNil and: [ readerProcess isTerminated not ] ]
]

{ #category : 'private' }
BeamEventStreamReader >> logError: anException [
	Transcript
		show: 'BeamEventStreamReader error: ';
		show: anException printString;
		cr
]

{ #category : 'private' }
BeamEventStreamReader >> openAndConsume [
	"Open a raw TCP socket to /EVENTS and drain SSE bytes.  I poll
	 `socket receiveDataTimeout: 1` instead of `socket waitForDataFor:`
	 because the latter has been observed to leave the reader suspended
	 in this Pharo image even when bytes arrive on the socket.  Polling
	 is reliable; the 200 ms idle sleep keeps CPU near zero."
	| serverAddress |
	serverAddress := application settings serverSocketAddress.
	client := Socket newTCP.
	client
		connectTo: (NetNameResolver addressForName: serverAddress ipOrName)
		port: serverAddress port
		waitForConnectionFor: 5.
	client sendData:
		('GET /EVENTS HTTP/1.1' , String crlf
			, 'Host: ' , serverAddress ipOrName , String crlf
			, 'Accept: text/event-stream' , String crlf
			, 'Connection: keep-alive' , String crlf
			, String crlf) asByteArray.
	"Drain response headers (best-effort; we don't validate them)."
	[ client receiveDataTimeout: 2 ] on: ConnectionTimedOut do: [ '' ].
	[ self pollUntilClosed: client ]
		on: ConnectionClosed do: [ "expected; my caller reconnects" ]
]

{ #category : 'private' }
BeamEventStreamReader >> payloadFrom: aDict keys: aKeysList [
	| payload |
	payload := Dictionary new.
	aKeysList do: [ :key |
		payload at: key put: (aDict at: key asString ifAbsent: [ nil ]) ].
	^ payload
]

{ #category : 'private' }
BeamEventStreamReader >> pollUntilClosed: aSocket [
	"Drain the socket until disconnect or `running` flips false.  `buf`
	 carries trailing partial lines across recv boundaries; chunked
	 transfer interleaves chunk-size lines with SSE data, so a frame
	 that straddles a recv would corrupt with naive `lines do:`."
	| buf |
	buf := String new.
	[ aSocket isConnected and: [ running ] ] whileTrue: [
		| data |
		data := [ aSocket receiveDataTimeout: 1 ]
			on: ConnectionTimedOut do: [ '' ].
		data isEmpty
			ifTrue: [ (Delay forMilliseconds: 200) wait ]
			ifFalse: [
				| lines |
				buf := buf , data asString.
				lines := buf lines.
				(buf endsWith: String lf)
					ifTrue: [
						lines do: [ :l | self handleLine: l ].
						buf := String new ]
					ifFalse: [
						lines size > 1 ifTrue: [
							(lines copyFrom: 1 to: lines size - 1) do: [ :l |
								self handleLine: l ].
							buf := lines last ] ] ] ]
]

{ #category : 'private' }
BeamEventStreamReader >> readLoop [
	"I open the SSE connection and reconnect while running.  Backoff
	 grows on consecutive failures so a down BEAM doesn't spam logs;
	 errors only log on transition (failing class changes) so a stable
	 outage produces one line, not one per second."
	| backoff lastError |
	backoff := 1.
	lastError := nil.
	[ running ] whileTrue: [
		[ self openAndConsume.
		  backoff := 1.
		  lastError := nil ]
			on: Error do: [ :e |
				e class = lastError ifFalse: [
					self logError: e.
					lastError := e class ] ].
		running ifTrue: [
			(Delay forSeconds: backoff) wait.
			backoff := (backoff * 2) min: 30 ] ]
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
