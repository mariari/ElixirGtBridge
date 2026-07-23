"
I am the GT-side cache that answers 'is this module name a loaded
Elixir module?' without per-query bridge calls.

I hold two sets — `resolved` (names BEAM has confirmed as loaded)
and `unresolved` (names BEAM has confirmed as not loaded).  Names
in neither set are unknown to me; consumers batch them and call
`classify:` to populate the cache from a single bridge query.

I subscribe weakly (via `BeamEventAnnouncer default weak`) to
`BeamModuleRecompiled`.  On each event I move the named module
from `unresolved` (if present) to `resolved` — additive
maintenance, no invalidation, no follow-up bridge call.

Sole writer / many readers: I am the only object that responds
to recompile events for the loaded-modules derivation.  Stylers
call `cache classify: name` and read the answer; they do not
subscribe to the underlying event themselves.  Expensive work
happens once here; cheap re-rendering happens N times in
consumers.

This implements the FRP shape laid out in
`learning_papers_frp_event_sourcing.md` and
`project_wrench_design_frp_alignment.md`.

### Public API

- `BeamModuleResolution default` — the singleton.
- `classify:` — return `#resolved`, `#unresolved`, or `#unknown`
  for a name.
- `recordResolved:unresolved:` — bulk-update from a bridge
  response.
- `reset` — drop both sets (debugging / image-wide rebuild).
"
Class {
	#name : 'BeamModuleResolution',
	#superclass : 'Object',
	#instVars : [
		'resolved',
		'unresolved',
		'generation'
	],
	#classInstVars : [
		'default'
	],
	#category : 'Gt4beam',
	#package : 'Gt4beam'
}

{ #category : 'instance creation' }
BeamModuleResolution class >> default [
	"I return the singleton, building (and subscribing) on first
	 access."
	^ default ifNil: [
		default := self new init.
		default ]
]

{ #category : 'class initialization' }
BeamModuleResolution class >> initialize [
	"I subscribe (idempotently) to the LanguageLink application
	 lifecycle so I can drop my singleton when the BEAM bridge
	 restarts.  Modules' resolved/unresolved status drifts on
	 restart -- modules unloaded across sessions, etc. -- so it
	 is simpler to start fresh than to try to reconcile.

	 Pharo calls me automatically on class definition / package
	 reload; for live patches via MCP `defineMethod` we have to
	 call me manually."
	LanguageLinkApplication announcer unsubscribe: self.
	LanguageLinkApplication announcer
		when: LanguageLinkStartAnnouncement
		send: #onApplicationStarted:
		to: self
]

{ #category : 'class initialization' }
BeamModuleResolution class >> onApplicationStarted: anAnnouncement [
	"Application (re)connected.  Drop the singleton so the next
	 `default` call rebuilds with an empty cache + fresh
	 `BeamModuleRecompiled` subscription."
	self reset
]

{ #category : 'class initialization' }
BeamModuleResolution class >> reset [
	"I drop the singleton — useful when image-wide state needs to
	 rebuild (e.g. application reconnect, debugging).  The next
	 `default` call rebuilds and re-subscribes."
	default := nil
]

{ #category : 'querying' }
BeamModuleResolution >> classify: aModuleName [
	"I return one of `#resolved`, `#unresolved`, or `#unknown` for
	 `aModuleName` (a Smalltalk string of the dotted Elixir name).
	 `#unknown` means we have not yet asked BEAM about this name —
	 the caller should batch unknowns and follow up with a
	 `recordResolved:unresolved:` after a bridge query."
	| name |
	name := aModuleName asString.
	(resolved includes: name) ifTrue: [ ^ #resolved ].
	(unresolved includes: name) ifTrue: [ ^ #unresolved ].
	^ #unknown
]

{ #category : 'accessing' }
BeamModuleResolution >> generation [
	"I count recompile events seen.  A derived fact computed from BEAM
	 module state records the generation it was computed at, so
	 currency becomes a comparison rather than a guess: a content hash
	 answers 'same input?' and cannot answer 'still current?'."
	^ generation ifNil: [ generation := 0 ]
]

{ #category : 'initialization' }
BeamModuleResolution >> init [
	"I initialize my two sets and wire up event subscription via
	 `subscribe`."
	resolved := Set new.
	unresolved := Set new.
	self subscribe
]

{ #category : 'subscriptions' }
BeamModuleResolution >> onBeamModuleRecompiled: anAnnouncement [
	"I move the named module from `unresolved` to `resolved`
	 additively — no invalidation, no bridge call.  If the module
	 was already in `resolved` (recompile of an existing module),
	 this is a no-op.  If it wasn't in either set (we never asked
	 about it), it lands in `resolved`.

	 I also advance the generation, which is what lets a consumer tell
	 a stale derivation from a current one."
	generation := self generation + 1.
	anAnnouncement mod ifNotNil: [ :modName |
		| name |
		name := modName asString.
		unresolved remove: name ifAbsent: [  ].
		resolved add: name ]
]

{ #category : 'updating' }
BeamModuleResolution >> recordResolved: aResolvedSet unresolved: anUnresolvedSet [
	"I incorporate a bridge response classifying a batch of
	 previously-unknown names.  `aResolvedSet` and
	 `anUnresolvedSet` are collections of name strings."
	aResolvedSet do: [ :each |
		unresolved remove: each asString ifAbsent: [  ].
		resolved add: each asString ].
	anUnresolvedSet do: [ :each |
		resolved remove: each asString ifAbsent: [  ].
		unresolved add: each asString ]
]

{ #category : 'accessing' }
BeamModuleResolution >> resolved [
	"For testing / introspection.  Consumers should use #classify:
	 instead of reading the set directly."
	^ resolved
]

{ #category : 'subscriptions' }
BeamModuleResolution >> subscribe [
	"I subscribe weakly to recompile events on the wildcard channel.
	 Weak means the announcer doesn't keep me alive — only my
	 class-side `default` reference and consumers' use of me do."
	BeamEventAnnouncer default weak
		when: BeamModuleRecompiled
		send: #onBeamModuleRecompiled:
		to: self
]

{ #category : 'accessing' }
BeamModuleResolution >> unresolved [
	"For testing / introspection.  Consumers should use #classify:
	 instead of reading the set directly."
	^ unresolved
]
