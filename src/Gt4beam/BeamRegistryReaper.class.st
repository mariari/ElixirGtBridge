"
I batch registry removals for proxies GT has collected.

PharoLink's finalizer sends one bridge message per collected proxy.  A
view over a large list collects tens of thousands at once, which
saturates the socket for seconds and stalls every other request.
{{gtClass:BeamProxyRegistryFinalizer}} enqueues into me instead, and a
background process flushes each handler's ids as one `remove_all`.
"
Class {
	#name : 'BeamRegistryReaper',
	#superclass : 'Object',
	#classInstVars : [
		'queue',
		'flusher'
	],
	#category : 'Gt4beam-Global',
	#package : 'Gt4beam',
	#tag : 'Global'
}

{ #category : 'accessing' }
BeamRegistryReaper class >> batchLimit [
	"Ids per message; a batch this size is a few tens of KB of source."
	^ 4096
]

{ #category : 'accessing' }
BeamRegistryReaper class >> flushDelayMilliseconds [
	^ 250
]

{ #category : 'accessing' }
BeamRegistryReaper class >> queue [
	^ queue ifNil: [ queue := WaitfreeQueue new: 4096 ]
]

{ #category : 'reaping' }
BeamRegistryReaper class >> ensureFlusher [
	(flusher notNil and: [ flusher isTerminated not ]) ifTrue: [ ^ self ].
	flusher := [ [ (Delay forMilliseconds: self flushDelayMilliseconds) wait.
	               [ self flush ] on: Error do: [ :e | ] ] repeat ]
		forkAt: Processor userBackgroundPriority
		named: 'Beam registry reaper'
]

{ #category : 'reaping' }
BeamRegistryReaper class >> flush [
	"Drain the queue into one message per handler."
	| batches assoc |
	batches := IdentityDictionary new.
	[ (assoc := self queue nextOrNil) isNil ] whileFalse: [
		(batches at: assoc key ifAbsentPut: [ OrderedCollection new ]) add: assoc value ].
	batches keysAndValuesDo: [ :handler :ids | self send: ids to: handler ]
]

{ #category : 'reaping' }
BeamRegistryReaper class >> removeId: anId handler: aHandler [
	"Enqueue only. Finalization runs at high priority and must not do I/O."
	self queue nextPut: aHandler -> anId.
	self ensureFlusher
]

{ #category : 'reaping' }
BeamRegistryReaper class >> send: ids to: aHandler [
	"One message per batchLimit ids, not one per id."
	| limit |
	aHandler application isRunning ifFalse: [ ^ self ].
	limit := self batchLimit.
	1 to: ids size by: limit do: [ :start |
		| chunk cf |
		chunk := ids copyFrom: start to: ((start + limit - 1) min: ids size).
		cf := aHandler newCommandFactory.
		cf << (aHandler removeIds: chunk).
		[ cf send ]
			on: LanguageLinkCommunicationError
			do: [ :ex | aHandler application isRunning ifTrue: [ ex pass ] ] ]
]
