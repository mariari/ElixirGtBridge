"
I turn a decoded module-event frame into an announcement on
{{gtClass:BeamEventAnnouncer}}.

I no longer read anything.  Module events arrive over the bridge's one
framed socket; {{gtClass:BeamLinkTcpMessageBroker}}'s reader parses each
frame and hands me the ones with a `kind`, and I dispatch them.

I am the SOLE publisher into `BeamEventAnnouncer`: no UI surface mints
events; everything flows through `GtBridge.CodeMonitor` ->
`GtBridge.Events.broadcast` -> the socket -> the broker -> me ->
`BeamEventAnnouncer`.

`BeamEventStreamReader for: anApp` returns a singleton per application,
which the broker holds for dispatch.
"
Class {
	#name : 'BeamEventStreamReader',
	#superclass : 'Object',
	#instVars : [
		'application'
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
	"Map an event `kind` -> instance-side selector that handles the
	 decoded frame.  Adding an event type means dropping a new handler
	 method and an entry here, no change to `dispatch:`."
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

{ #category : 'private' }
BeamEventStreamReader >> payloadFrom: aDict keys: aKeysList [
	| payload |
	payload := Dictionary new.
	aKeysList do: [ :key |
		payload at: key put: (aDict at: key asString ifAbsent: [ nil ]) ].
	^ payload
]
