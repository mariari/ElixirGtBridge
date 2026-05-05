"
I am the GT-side dispatcher for BEAM events received from the bridge.

I provide two subscription channels:

  - **Per-module announcer** via `BeamEventAnnouncer for: 'Foo.Bar'`.
    Subscribers registered here only hear events for that specific
    module. Use this when a coder/element cares about exactly one
    module — the common case.

  - **Default singleton** via `BeamEventAnnouncer default`.
    Subscribers here hear every event regardless of which module fired
    it. Use this for wildcard listeners (e.g. ElixirCoderBrowser
    invalidating its rawNodes cache on any recompile).

The GT-side translator that reads bridge responses calls
`BeamEventAnnouncer announceRecompiled: aModuleName` per recompiled
module; that dispatches to both the per-module announcer (if any
subscribers exist) and the default singleton.

Subscriptions should always be `weak` so closed inspectors / GC'd
coders don't pin themselves alive in the registry:

    (BeamEventAnnouncer for: self moduleName) weak
        when: BeamModuleRecompiled
        send: #onBeamModuleRecompiled:
        to: self.

    BeamEventAnnouncer default unsubscribe: self.

Bloc elements with non-trivial event-handler work (e.g. tree refresh,
sidebar fan-out) should subscribe in `onAddedToSceneGraph` and
unsubscribe in `onRemovedFromSceneGraph` to keep background instances
silent.
"
Class {
	#name : 'BeamEventAnnouncer',
	#superclass : 'Announcer',
	#classInstVars : [
		'default',
		'announcers'
	],
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}

{ #category : 'announcing' }
BeamEventAnnouncer class >> announceCompileFailedFor: aModuleName application: anApp errors: aListOfErrors [
	"Per-module + default fan-out, mirroring announceRecompiledFrom:.
	 Also pops a `BeamCompileFailureNotification` whose Open button
	 spawns the offending module's coder."
	| announcement perModule |
	announcement := BeamCompileFailed mod: aModuleName errors: aListOfErrors.
	perModule := self announcers at: aModuleName ifAbsent: [ nil ].
	perModule ifNotNil: [ perModule announce: announcement ].
	self default announce: announcement.
	GtWorld showNotification:
		(self compileFailureNotificationFor: announcement application: anApp)
]

{ #category : 'announcing' }
BeamEventAnnouncer class >> announceCompileFailedFor: aModuleName errors: aListOfErrors [
	"Convenience for callers without an application reference."
	^ self announceCompileFailedFor: aModuleName application: nil errors: aListOfErrors
]

{ #category : 'announcing' }
BeamEventAnnouncer class >> compileFailureNotificationFor: anAnnouncement application: anApp [
	"Build the notification from the first error (offending module /
	 line / message) with announcement's mod as fallback."
	| first |
	first := anAnnouncement errors ifNotNil: [ :e |
		e isEmpty ifTrue: [ nil ] ifFalse: [ e first ] ].
	^ BeamCompileFailureNotification new
		moduleName: ((self read: #module from: first) ifNil: [ anAnnouncement mod ]) asString;
		sourcePath: (self read: #file from: first);
		line: (self read: #line from: first);
		errorMessage: ((self read: #message from: first) ifNil: [ 'compile failed' ]) asString;
		functionName: ((self read: #function from: first) ifNotNil: [ :f | f asString ]);
		arity: (self read: #arity from: first);
		application: anApp;
		yourself
]

{ #category : 'announcing' }
BeamEventAnnouncer class >> read: aKey from: anEntry [
	"Polymorphic field read that handles both Smalltalk Dictionary
	 entries (tests) and BeamProxyObject map proxies (live bridge)."
	anEntry ifNil: [ ^ nil ].
	^ (anEntry respondsTo: #attributeAt:)
		ifTrue: [ anEntry attributeAt: aKey ]
		ifFalse: [ anEntry at: aKey ifAbsent: [ nil ] ]
]

{ #category : 'announcing' }
BeamEventAnnouncer class >> announceSourceWrittenFor: aModuleName fromPayload: aPayload [
	"Per-module + default fan-out for the disk-write fact."
	| announcement perModule |
	announcement := BeamModuleSourceWritten fromPayload: aPayload mod: aModuleName.
	perModule := self announcers at: aModuleName ifAbsent: [ nil ].
	perModule ifNotNil: [ perModule announce: announcement ].
	self default announce: announcement
]

{ #category : 'announcing' }
BeamEventAnnouncer class >> announceRecompiled: aModuleName [
	"I am a thin wrapper around `announceRecompiledFrom:` for callers
	 that only have a bare module name (e.g. unit-style examples that
	 do not exercise the bridge). Production saves go through
	 `announceRecompiledFrom:` so subscribers receive the new source +
	 functions inline."

	^ self announceRecompiledFrom:
		(Dictionary new at: #mod put: aModuleName; yourself)
]

{ #category : 'announcing' }
BeamEventAnnouncer class >> announceRecompiledFrom: aDictionary [
	"I am the single dispatch entry point for module recompile events.
	 I fire the announcement on the per-module announcer (so narrow
	 subscribers wake only for their module) AND on the default
	 singleton (so wildcard subscribers continue to hear everything).

	 Pass a dict from `GtBridge.HotReload.reload`'s `recompiled` list
	 (keys: `mod`, `source_hash`, `source`, `functions`). The directly
	 saved module's payload includes `source` + `functions`; sibling
	 modules carry `mod` only and let subscribers fall back to a
	 bridge call if they need fresher data."

	| announcement modName perModule |
	announcement := BeamModuleRecompiled fromPayload: aDictionary.
	modName := announcement mod.

	perModule := self announcers at: modName ifAbsent: [ nil ].
	perModule ifNotNil: [ perModule announce: announcement ].

	self default announce: announcement
]

{ #category : 'accessing' }
BeamEventAnnouncer class >> announcers [
	"Lazy per-module announcer registry. Keyed by bare module name."

	^ announcers ifNil: [ announcers := Dictionary new ]
]

{ #category : 'accessing' }
BeamEventAnnouncer class >> default [
	^ default ifNil: [ default := self new ]
]

{ #category : 'accessing' }
BeamEventAnnouncer class >> for: aModuleName [
	"I return the announcer that fires only for events on
	 `aModuleName`. Lazy-created on first access; survives until
	 `reset` is called or the image is shut down. Subscribers
	 registering here only hear events for this specific module."

	^ self announcers at: aModuleName ifAbsentPut: [ Announcer new ]
]

{ #category : 'gt-views' }
BeamEventAnnouncer class >> gtFanoutFor: aView [
	"I render the live dispatcher graph: the default singleton and
	 each per-module announcer with its subscriber receivers grouped
	 by class.  Useful for spotting accidental retention or unexpected
	 listeners on a particular module.

	 Every node is the actual underlying model — clicking opens an
	 inspector on the announcer / class / subscriber list itself, not
	 on a placeholder string.  Per-class subscriber groups carry the
	 receiver Array so you can drill into any individual subscriber."

	<gtClassView>
	^ aView mondrian
		title: 'Fanout';
		priority: 5;
		painting: [ :aMondrian |
			| nodes edges subscribersOf labels colors |
			nodes := OrderedCollection new.
			edges := OrderedCollection new.
			labels := IdentityDictionary new.
			colors := IdentityDictionary new.

			"Safely extract subscriber receivers from an Announcer."
			subscribersOf := [ :ann |
				[ ann subscriptions subscriptions
					ifNil: [ #() ]
					ifNotNil: [ :subs | subs collect: [ :s | s subscriber ] ] ]
					on: Error do: [ #() ] ].

			"Dispatcher root: the class itself.  Default singleton: the
			 actual instance."
			nodes add: self.
			labels at: self put: 'dispatcher'.
			colors at: self put: (Color fromHexString: '#fce8e6').

			nodes add: self default.
			labels at: self default put: 'default (wildcard)'.
			colors at: self default put: (Color fromHexString: '#fff8d6').
			edges add: self -> self default.

			"Per-module announcers — actual instances, label is the
			 module name."
			self announcers keys asArray sorted do: [ :modName |
				| ann |
				ann := self announcers at: modName.
				nodes add: ann.
				labels at: ann put: modName.
				colors at: ann put: (Color fromHexString: '#e8f0fe').
				edges add: self -> ann ].

			"Subscriber group nodes — one Array per (announcer, receiver-class)
			 pair so the picture stays readable when many of the same kind
			 listen to the same announcer.  Clicking opens an inspector on
			 the receiver Array."
			(OrderedCollection new
				add: self default -> 'default';
				addAll: (self announcers keys asArray sorted collect: [ :k |
					(self announcers at: k) -> k ]);
				yourself) do: [ :pair |
					| ann annLabel byClass |
					ann := pair key.
					annLabel := pair value.
					byClass := (subscribersOf value: ann)
						groupedBy: [ :s | s class name ].
					byClass keysAndValuesDo: [ :className :receivers |
						| groupNode |
						groupNode := receivers asArray.
						nodes add: groupNode.
						labels at: groupNode put:
							annLabel , ' → ' , className , ' (' , receivers size asString , ')'.
						colors at: groupNode put: (Color gray alpha: 0.15).
						edges add: ann -> groupNode ] ].

			aMondrian nodes
				shape: [ :n |
					BrLabel new
						aptitude: BrGlamorousLabelAptitude new;
						text: (labels at: n);
						padding: (BlInsets all: 6);
						background: (colors at: n);
						geometry: (BlRoundedRectangleGeometry cornerRadius: 6) ];
				with: nodes asArray.

			aMondrian edges
				connect: edges asArray from: #key to: #value.

			aMondrian layout horizontalTree
				nodeDistance: 8;
				levelDistance: 40 ]
]

{ #category : 'accessing' }
BeamEventAnnouncer class >> reset [
	"Drop the singleton and the per-module registry. Use in tests; in
	 normal operation subscribers should `unsubscribe: self` rather than
	 tear down the announcer."

	default := nil.
	announcers := nil
]
