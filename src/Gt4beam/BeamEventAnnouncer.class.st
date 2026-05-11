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
	^ self
		announceCompileFailedFor: aModuleName
		application: anApp
		errors: aListOfErrors
		functionHint: nil
		arityHint: nil
]

{ #category : 'announcing' }
BeamEventAnnouncer class >> announceCompileFailedFor: aModuleName application: anApp errors: aListOfErrors functionHint: aFunctionName arityHint: anArity [
	"`aFunctionName` / `anArity` are GT-side fallbacks for when the
	 bridge couldn't identify the function (parse failure on the saved
	 file makes Analysis.functions_in_source return [], module-level
	 diagnostics carry no usable line)."
	| announcement |
	announcement := BeamCompileFailed mod: aModuleName errors: aListOfErrors.
	self dispatch: announcement on: aModuleName.
	GtWorld showNotification:
		(self compileFailureNotificationFor: announcement
			application: anApp
			functionHint: aFunctionName
			arityHint: anArity)
]

{ #category : 'announcing' }
BeamEventAnnouncer class >> announceCompileFailedFor: aModuleName errors: aListOfErrors [
	"Convenience for callers without an application reference."
	^ self announceCompileFailedFor: aModuleName application: nil errors: aListOfErrors
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

	| announcement |
	announcement := BeamModuleRecompiled fromPayload: aDictionary.
	self dispatch: announcement on: announcement mod
]

{ #category : 'announcing' }
BeamEventAnnouncer class >> announceSourceRemoved: aModuleName [
	"Source artifact for `aModuleName` was deleted (e.g. user trashed
	 the file).  I fan out on per-module + default so caches keyed on
	 the module clear themselves and the resolution cache flips the
	 name back to `unresolved`."

	self dispatch: (BeamModuleSourceRemoved mod: aModuleName) on: aModuleName
]

{ #category : 'announcing' }
BeamEventAnnouncer class >> announceSourceWrittenFor: aModuleName fromPayload: aPayload [
	"Per-module + default fan-out for the disk-write fact."
	self
		dispatch: (BeamModuleSourceWritten fromPayload: aPayload mod: aModuleName)
		on: aModuleName
]

{ #category : 'accessing' }
BeamEventAnnouncer class >> announcers [
	"Lazy per-module announcer registry. Keyed by bare module name."

	^ announcers ifNil: [ announcers := Dictionary new ]
]

{ #category : 'announcing' }
BeamEventAnnouncer class >> compileFailureNotificationFor: anAnnouncement application: anApp [
	^ self
		compileFailureNotificationFor: anAnnouncement
		application: anApp
		functionHint: nil
		arityHint: nil
]

{ #category : 'announcing' }
BeamEventAnnouncer class >> compileFailureNotificationFor: anAnnouncement application: anApp functionHint: aFunctionName arityHint: anArity [
	"Build the notification from the first error.  Function / arity
	 fall back to the caller-supplied hints when the error entry
	 doesn't carry them."
	| first |
	first := anAnnouncement errors ifNotNil: [ :e |
		e isEmpty ifTrue: [ nil ] ifFalse: [ e first ] ].
	^ BeamCompileFailureNotification new
		moduleName: ((BeamModuleAnnouncement payloadValue: #module from: first) ifNil: [ anAnnouncement mod ]) asString;
		sourcePath: (BeamModuleAnnouncement payloadValue: #file from: first);
		line: (BeamModuleAnnouncement payloadValue: #line from: first);
		errorMessage: ((BeamModuleAnnouncement payloadValue: #message from: first) ifNil: [ 'compile failed' ]) asString;
		functionName: (((BeamModuleAnnouncement payloadValue: #function from: first)
			ifNotNil: [ :f | f asString ]) ifNil: [ aFunctionName ]);
		arity: ((BeamModuleAnnouncement payloadValue: #arity from: first) ifNil: [ anArity ]);
		application: anApp;
		yourself
]

{ #category : 'accessing' }
BeamEventAnnouncer class >> default [
	^ default ifNil: [ default := self new ]
]

{ #category : 'announcing' }
BeamEventAnnouncer class >> dispatch: anAnnouncement on: aModuleName [
	"Fire `anAnnouncement` on the per-module announcer (if any subscribers
	 are listening narrowly) AND on the default singleton (so wildcard
	 subscribers continue to hear everything)."
	| perModule |
	perModule := self announcers at: aModuleName ifAbsent: [ nil ].
	perModule ifNotNil: [ perModule announce: anAnnouncement ].
	self default announce: anAnnouncement
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
			| nodes edges labels |
			nodes := OrderedCollection new.
			edges := OrderedCollection new.
			labels := IdentityDictionary new.

			"Dispatcher root + default singleton."
			nodes add: self.
			labels at: self put: 'dispatcher'.

			nodes add: self default.
			labels at: self default put: 'default (wildcard)'.
			edges add: self -> self default.

			"Per-module announcers, actual instances; label is the
			 module name."
			self announcers keys asArray sorted do: [ :modName |
				| ann |
				ann := self announcers at: modName.
				nodes add: ann.
				labels at: ann put: modName.
				edges add: self -> ann ].

			"FRP shape per announcer (announcer -> cache -> consumers)
			 lives on `BeamModuleSourceCache class >> addFanoutFor:...`."
			(OrderedCollection new
				add: self default;
				addAll: (self announcers keys asArray sorted
					collect: [ :k | self announcers at: k ]);
				yourself) do: [ :ann |
					BeamModuleSourceCache
						addFanoutFor: ann
						rootedAt: ann
						nodes: nodes
						edges: edges
						labels: labels ].

			BeamMondrianHelpers
				paintLabeledGraphOn: aMondrian
				nodes: nodes edges: edges
				labels: labels
				layout: [ :l | l horizontalTree nodeDistance: 8; levelDistance: 40 ] ]
]

{ #category : 'accessing' }
BeamEventAnnouncer class >> reset [
	"Drop the singleton and the per-module registry. Use in tests; in
	 normal operation subscribers should `unsubscribe: self` rather than
	 tear down the announcer."

	default := nil.
	announcers := nil
]
