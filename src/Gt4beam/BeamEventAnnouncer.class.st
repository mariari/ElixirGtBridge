"
I am the GT-side singleton announcer for BEAM events received from the
bridge.

I sit between the bridge HTTP/SSE inbound channel (Elixir-side
EventBroker) and Bloc surfaces that want to react to module recompiles,
compile failures, and module removals.

Subscribers register and unsubscribe with the standard Announcer protocol:

    BeamEventAnnouncer default
        when: BeamModuleRecompiled
        do: [ :ann | ... ]
        for: self.

    BeamEventAnnouncer default unsubscribe: self.

Bloc elements should subscribe in `onAddedToSceneGraph` and unsubscribe in
`onRemovedFromSceneGraph` to avoid leaks.

Publishers (the GT-side save handler that knows which modules recompiled,
or the future SSE inbound dispatcher) call:

    BeamEventAnnouncer default announce:
        (BeamModuleRecompiled mod: #'Elixir.Foo.Bar' sourceHash: nil).
"
Class {
	#name : 'BeamEventAnnouncer',
	#superclass : 'Announcer',
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events',
	#classInstVars : [ 'default' ]
}

{ #category : 'accessing' }
BeamEventAnnouncer class >> default [
	^ default ifNil: [ default := self new ]
]

{ #category : 'accessing' }
BeamEventAnnouncer class >> reset [
	"Drop the singleton. Use in tests; in normal operation subscribers should
	use unsubscribe: self rather than tearing down the announcer."

	default := nil
]
