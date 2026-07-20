"
I count and time the bridge calls an operation makes.

PharoLink already emits `PharoLinkRequestSignal` before every HTTP
request and `PharoLinkResponseSignal` when the reply lands, so no new
instrumentation is needed.  I start a `MemoryLogger` on their common
parent, then pair the two by `commandId`.

Pairing is by id rather than by arrival order because the request and
its response run on different Pharo processes, so the log is not
reliably interleaved.

    | p |
    p := BeamBridgeProfiler new start.
    someObject someOperation.
    p stop.
    p hotspots

A statement with a high count is the interesting result: repetition is
a batching opportunity, where a single slow call usually is not.
"
Class {
	#name : 'BeamBridgeProfiler',
	#superclass : 'Object',
	#instVars : [
		'logger'
	],
	#category : 'Gt4beam-Profiling',
	#package : 'Gt4beam',
	#tag : 'Profiling'
}

{ #category : 'accessing' }
BeamBridgeProfiler >> calls [
	"I return one entry per completed bridge call as
	 `statement -> durationInMicroseconds`, correlated by commandId."
	| requests result |
	logger ifNil: [ ^ #() ].
	requests := Dictionary new.
	logger recordings do: [ :s |
		(s isKindOf: PharoLinkRequestSignal) ifTrue: [
			requests at: (s request at: #commandId ifAbsent: [ nil ]) put: s ] ].
	result := OrderedCollection new.
	logger recordings do: [ :s |
		(s isKindOf: PharoLinkResponseSignal) ifTrue: [
			| req |
			req := requests at: (s response at: 'id' ifAbsent: [ nil ]) ifAbsent: [ nil ].
			req ifNotNil: [
				result add: (req request at: #statements ifAbsent: [ '?' ]) asString
					-> (s timestamp - req timestamp) asMicroseconds ] ] ].
	^ result
]

{ #category : 'accessing' }
BeamBridgeProfiler >> hotspots [
	"I group calls by statement, worst total time first, as
	 `statement -> { count. totalMicros. maxMicros }`."
	| grouped |
	grouped := Dictionary new.
	self calls do: [ :assoc |
		| entry |
		entry := grouped at: assoc key ifAbsentPut: [ Array with: 0 with: 0 with: 0 ].
		grouped at: assoc key put: (Array
			with: (entry at: 1) + 1
			with: (entry at: 2) + assoc value
			with: ((entry at: 3) max: assoc value)) ].
	^ grouped associations asSortedCollection: [ :a :b |
		(a value at: 2) > (b value at: 2) ]
]

{ #category : 'running' }
BeamBridgeProfiler >> start [
	"I begin recording every bridge request and response."
	logger := MemoryLogger new startFor: PharoLinkSignal.
	^ self
]

{ #category : 'running' }
BeamBridgeProfiler >> stop [
	logger ifNotNil: [ logger stop ].
	^ self
]
