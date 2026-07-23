"
I speak to the BEAM over one persistent, length-framed TCP socket that
carries both directions.

The HTTP broker used three channels: an outbound ZnClient per request, an
inbound ZnServer for callbacks, and {{gtClass:BeamEventStreamReader}}'s SSE
poll for module events.  I replace all three.  A request is a framed write
that returns immediately; its answer rides back as an inbound frame, which
is the async message model the framework was built for (the HTTP broker's
`sendAsyncMessage:` returning the answer inline was the hack).

Frames are a 4-byte big-endian length followed by that many JSON bytes,
matching Erlang's `packet: 4` on the BEAM side.  My reader tells the two
kinds apart on arrival: a frame with a `type` is a reply, which I route
through the same `handleRMessage:` path the inbound HTTP server used, so it
resolves its promise; a frame with a `kind` is a module event, which I hand
to an event reader for dispatch.
"
Class {
	#name : 'BeamLinkTcpMessageBroker',
	#superclass : 'PharoLinkAbstractMessageBroker',
	#instVars : [
		'socket',
		'readerProcess',
		'running',
		'eventReader'
	],
	#category : 'Gt4beam-Pharo-MessageBroker',
	#package : 'Gt4beam',
	#tag : 'Pharo-MessageBroker'
}

{ #category : 'accessing' }
BeamLinkTcpMessageBroker class >> serializerClass [
	^ ElixirLinkNeoJsonSerializer
]

{ #category : 'accessing' }
BeamLinkTcpMessageBroker >> eventReader: aReader [
	eventReader := aReader
]

{ #category : 'accessing' }
BeamLinkTcpMessageBroker >> tcpPort [
	"The framed transport listens one port above the HTTP one."
	^ settings serverSocketAddress port + 1
]

{ #category : 'testing' }
BeamLinkTcpMessageBroker >> isRunning [
	^ running == true and: [ socket notNil and: [ socket isConnected ] ]
]

{ #category : 'lifecycle' }
BeamLinkTcpMessageBroker >> start [
	| addr |
	addr := settings serverSocketAddress.
	socket := Socket newTCP.
	socket
		connectTo: (NetNameResolver addressForName: addr ipOrName)
		port: self tcpPort
		waitForConnectionFor: 5.
	running := true.
	readerProcess := [ self readLoop ] forkNamed: 'BeamLinkTcp reader'.
	^ self
]

{ #category : 'lifecycle' }
BeamLinkTcpMessageBroker >> stop [
	running := false.
	readerProcess ifNotNil: [ readerProcess terminate. readerProcess := nil ].
	socket ifNotNil: [ socket closeAndDestroy. socket := nil ]
]

{ #category : 'sending' }
BeamLinkTcpMessageBroker >> primSendMessage: dict [
	| json len frame |
	PharoLinkRequestSignal new request: dict; emit.
	json := (self serializer serialize: dict) utf8Encoded.
	len := json size.
	frame := ByteArray new: 4 + len.
	frame at: 1 put: (len >> 24 bitAnd: 255); at: 2 put: (len >> 16 bitAnd: 255);
	      at: 3 put: (len >> 8 bitAnd: 255); at: 4 put: (len bitAnd: 255).
	frame replaceFrom: 5 to: frame size with: json startingAt: 1.
	socket sendData: frame
]

{ #category : 'sending' }
BeamLinkTcpMessageBroker >> sendAsyncMessage: msg [
	"Fire and forget: the answer rides back as an inbound frame the reader
	 resolves the promise from."
	self primSendMessage: msg encode
]

{ #category : 'sending' }
BeamLinkTcpMessageBroker >> sendSyncMessage: msg [
	"Evals are async; a sync message still resolves through the promise the
	 reader signals."
	^ self sendAsyncMessage: msg
]

{ #category : 'reading' }
BeamLinkTcpMessageBroker >> readLoop [
	"Accumulate bytes and pull whole frames out, matching the read pattern
	 the SSE reader proved reliable in this image.  A frame is a 4-byte
	 big-endian length followed by that many JSON bytes.  Requests and
	 events share this stream: a frame with a `type` is a reply that
	 resolves its promise, one with a `kind` is a module event."
	| buffer |
	buffer := ByteArray new.
	[ running ] whileTrue: [
		[ | data |
		  data := [ (socket notNil and: [ socket isConnected ])
					ifTrue: [ socket receiveDataTimeout: 1 ]
					ifFalse: [ running := false. '' ] ]
				on: ConnectionTimedOut , ConnectionClosed
				do: [ :e | e class = ConnectionClosed ifTrue: [ running := false ]. '' ].
		  data isEmpty
			ifTrue: [ (Delay forMilliseconds: 50) wait ]
			ifFalse: [ buffer := self drainFrames: buffer , data asByteArray ] ]
			on: Error do: [ :e | self debugMode ifTrue: [ e pass ] ] ]
]

{ #category : 'reading' }
BeamLinkTcpMessageBroker >> drainFrames: aBuffer [
	"Dispatch every complete frame in aBuffer, return the remainder."
	| buf len |
	buf := aBuffer.
	[ buf size >= 4 and: [ buf size >= (4 + (self frameLenOf: buf)) ] ] whileTrue: [
		len := self frameLenOf: buf.
		self dispatchFrame: (self serializer deserialize: (buf copyFrom: 5 to: 4 + len) utf8Decoded).
		buf := buf copyFrom: 5 + len to: buf size ].
	^ buf
]

{ #category : 'reading' }
BeamLinkTcpMessageBroker >> frameLenOf: buf [
	^ ((buf at: 1) << 24) + ((buf at: 2) << 16) + ((buf at: 3) << 8) + (buf at: 4)
]

{ #category : 'reading' }
BeamLinkTcpMessageBroker >> dispatchFrame: dict [
	PharoLinkResponseSignal new response: dict; emit.
	(dict includesKey: 'type')
		ifTrue: [ self handleRMessage: dict ]
		ifFalse: [ (dict includesKey: 'kind') ifTrue: [ self dispatchEvent: dict ] ]
]

{ #category : 'reading' }
BeamLinkTcpMessageBroker >> handleRMessage: dict [
	"A reply resolves its promise the same way the /EVAL callback did:
	 its `type` (#EVAL) maps to LanguageLinkUpdatePromiseMessage, whose
	 registered handler signals the promise."
	| msgClass |
	msgClass := self resolveMessageFromType: (dict at: #type).
	^ self handle: dict reverseMessageClass: msgClass
]

{ #category : 'reading' }
BeamLinkTcpMessageBroker >> dispatchEvent: dict [
	eventReader ifNotNil: [ eventReader dispatch: dict ]
]
