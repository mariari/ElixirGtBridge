"
I read the bridge's `/EVENTS` SSE stream and fire announcements on
`BeamEventAnnouncer default`.  Singleton per `BeamLinkApplication`;
auto-reconnects on stream end.
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
	"I block in MY process until the connection drops.  Inlining the
	 read loop matters: ZdcSocketStream>>liveReadLoopDo: is fork-and-
	 forget, which would let my readLoop spawn a new reader every
	 second and pop a debugger per zombie when the bridge dies."
	| serverAddress url stream |
	serverAddress := application settings serverSocketAddress.
	url := 'http://' , serverAddress ipOrName , ':'
		, serverAddress port asString , '/EVENTS'.
	client := ZnClient new
		url: url;
		method: #GET;
		streaming: true;
		getConnectionAndExecute.
	stream := client connection.
	[ self readUntilClosed: stream ]
		on: ConnectionClosed do: [ "expected; my caller reconnects" ]
]

{ #category : 'private' }
BeamEventStreamReader >> readUntilClosed: stream [
	"Drain the stream until the connection drops or `running` flips
	 false.  `pending` carries trailing partial lines across iterations
	 — large frames (e.g. inline source payloads) can straddle TCP
	 read boundaries and a naive `lines do:` would corrupt them."
	| readBuffer socket pending |
	readBuffer := stream instVarNamed: #readBuffer.
	socket := stream instVarNamed: #socket.
	pending := String new.
	[ stream isConnected and: [ running ] ] whileTrue: [
		| available |
		available := readBuffer availableForReading.
		available > 0 ifTrue: [
			| chunk text lines |
			chunk := readBuffer contents asString.
			readBuffer advanceReadPointer: available.
			text := pending , chunk.
			lines := text lines.
			(text endsWith: String lf)
				ifTrue: [
					pending := String new.
					lines do: [ :l | self handleLine: l ] ]
				ifFalse: [
					lines size > 1 ifTrue: [
						(lines copyFrom: 1 to: lines size - 1) do: [ :l |
							self handleLine: l ] ].
					pending := lines last ] ].
		readBuffer isEmpty ifTrue: [
			stream fillReadBufferNoWait.
			(readBuffer isEmpty and: [ stream isConnected ]) ifTrue: [
				[ socket waitForDataFor: 5.
				  stream fillReadBufferNoWait ]
					on: ConnectionTimedOut do: [ "no data; loop" ] ] ] ]
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
	 Later topics extend me with clauses for their event kinds."

	| kind |
	kind := aDict at: 'kind' ifAbsent: [ ^ self ].
	kind = 'recompiled' ifTrue: [
		^ BeamEventAnnouncer announceRecompiledFrom: (Dictionary new
			at: #mod put: (aDict at: 'mod' ifAbsent: [ nil ]);
			at: #source_hash put: (aDict at: 'source_hash' ifAbsent: [ nil ]);
			at: #source put: (aDict at: 'source' ifAbsent: [ nil ]);
			at: #functions put: (aDict at: 'functions' ifAbsent: [ nil ]);
			yourself) ]
]

{ #category : 'private' }
BeamEventStreamReader >> logError: anException [
	Transcript
		show: 'BeamEventStreamReader error: ';
		show: anException printString;
		cr
]
