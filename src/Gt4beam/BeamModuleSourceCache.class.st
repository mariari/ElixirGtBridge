"
I am a per-module cache of function source text — a value-typed
projection of `BeamModuleRecompiled` events for one Elixir module.

One instance per module, looked up via `for: aModuleName`.  The
class-side registry is a `WeakValueDictionary` so caches with no
live consumers get GC'd; my own subscription to the per-module
announcer is `weak`, so the announcer doesn't keep me alive
either.  Lifecycle:

- *Birth* — `for: 'Foo'` builds an instance, registers weakly,
  subscribes weakly to `BeamEventAnnouncer for: 'Foo'`.
- *Active* — consumers (expanders, function coders) hold me
  strongly via instvar; recompile events update my source map
  and fan out narrow `BeamModuleSourceChanged` events on the
  same per-module announcer.
- *Death* — when no consumer holds me, my registry slot and
  subscription are both weak → GC collects me, subscription
  cleans up automatically.  Next `for: 'Foo'` builds fresh.

I am the sole subscriber to `BeamModuleRecompiled` for my module.
Consumers subscribe to `BeamModuleSourceChanged` instead — the
narrow event lets them filter by their target function/arity in
their handler instead of reaching for the announcement payload.

See `project_wrench_design_frp_alignment.md` for the recipe and
the per-module cache lifecycle rules.

### Public API

- `BeamModuleSourceCache for: aModName` — look up or build the
  cache for `aModName`.
- `sourceForFunction: aName arity: anArity` — return the cached
  source string or nil if not yet seen.
"
Class {
	#name : 'BeamModuleSourceCache',
	#superclass : 'Object',
	#instVars : [
		'mod',
		'sources',
		'entries'
	],
	#classInstVars : [
		'caches'
	],
	#category : 'Gt4beam-Caches',
	#package : 'Gt4beam'
}

{ #category : 'instance creation' }
BeamModuleSourceCache class >> for: aModuleName [
	"I return the cache for `aModuleName`, building (and weakly
	 registering + subscribing) a fresh one on first call.  The
	 class-side registry is a WeakValueDictionary — caches with no
	 live consumers GC away and the next call rebuilds."
	| name |
	name := aModuleName asString.
	caches ifNil: [ caches := WeakValueDictionary new ].
	^ caches at: name ifAbsentPut: [
		self new
			mod: name;
			subscribe;
			yourself ]
]

{ #category : 'gt-views' }
BeamModuleSourceCache class >> gtFlowFor: aView [
	"I render the static architecture of the cache: input event,
	 the cache itself as the sole subscriber, output events fanned
	 out, and the consumer classes that subscribe to each.

	 Sibling of `gtLifecycleFor:` — that view shows live runtime
	 state (instances + actual subscribers); this view shows the
	 *intended* shape, useful as docs even when no caches exist."

	<gtClassView>
	^ aView mondrian
		title: 'Flow';
		priority: 4;
		painting: [ :aMondrian |
			| nodes edges labels colors |
			nodes := OrderedCollection new.
			edges := OrderedCollection new.
			labels := IdentityDictionary new.
			colors := IdentityDictionary new.

			"Input event."
			nodes add: BeamModuleRecompiled.
			labels at: BeamModuleRecompiled
				put: 'BeamModuleRecompiled (input from BEAM)'.
			colors at: BeamModuleRecompiled
				put: (Color fromHexString: '#fce8e6').

			"Cache — sole subscriber per module."
			nodes add: self.
			labels at: self
				put: 'BeamModuleSourceCache (per-module, sole subscriber)'.
			colors at: self put: (Color fromHexString: '#e8f0fe').
			edges add: BeamModuleRecompiled -> self.

			"Output events."
			{ BeamModuleSourceChanged.
				BeamModuleEntriesUpdated } do: [ :evt |
					nodes add: evt.
					labels at: evt put: evt name.
					colors at: evt put: (Color fromHexString: '#fff8d6').
					edges add: self -> evt ].

			"Consumers wired to each output."
			{ BeamModuleSourceChanged -> ElixirFunctionExpanderAttribute.
				BeamModuleEntriesUpdated -> ElixirModuleCoder } do: [ :pair |
					(nodes includes: pair value) ifFalse: [
						nodes add: pair value.
						labels at: pair value put: pair value name.
						colors at: pair value
							put: (Color gray alpha: 0.15) ].
					edges add: pair key -> pair value ].

			BeamMondrianHelpers
				paintLabeledGraphOn: aMondrian
				nodes: nodes edges: edges
				labels: labels colors: colors
				layout: [ :l | l verticalTree nodeDistance: 12; levelDistance: 30 ] ]
]

{ #category : 'gt-views' }
BeamModuleSourceCache class >> gtLifecycleFor: aView [
	"I render the live cache graph: each currently-alive per-module
	 cache instance plus the consumer receivers subscribed to its
	 narrow events.  Useful for spotting accidental retention or for
	 watching a cache GC away as you close inspectors.

	 Mirrors `BeamEventAnnouncer class >> gtFanoutFor:`'s style —
	 every node is the underlying model, clicks open inspectors."

	<gtClassView>
	^ aView mondrian
		title: 'Lifecycle';
		priority: 5;
		painting: [ :aMondrian |
			| nodes edges labels colors live |
			nodes := OrderedCollection new.
			edges := OrderedCollection new.
			labels := IdentityDictionary new.
			colors := IdentityDictionary new.

			nodes add: self.
			labels at: self put: 'BeamModuleSourceCache'.
			colors at: self put: (Color fromHexString: '#fce8e6').

			live := self liveCaches.
			live do: [ :cache |
				| ann otherSubs |
				nodes add: cache.
				labels at: cache put:
					cache mod , ' (' ,
					cache sources size asString , ' fns)'.
				colors at: cache put: (Color fromHexString: '#e8f0fe').
				edges add: self -> cache.

				"Show subscribers of the per-module announcer that aren't
				 the cache itself -- those are the actual downstream
				 consumers (expanders, function coders, etc.)."
				ann := BeamEventAnnouncer for: cache mod.
				otherSubs := (BeamMondrianHelpers subscribersOf: ann)
					reject: [ :s | s == cache ].
				(otherSubs groupedBy: [ :s | s class name ])
					keysAndValuesDo: [ :clsName :receivers |
						| groupNode |
						groupNode := receivers asArray.
						nodes add: groupNode.
						labels at: groupNode put:
							clsName , ' (' , receivers size asString , ')'.
						colors at: groupNode put: (Color gray alpha: 0.15).
						edges add: cache -> groupNode ] ].

			BeamMondrianHelpers
				paintLabeledGraphOn: aMondrian
				nodes: nodes edges: edges
				labels: labels colors: colors
				layout: [ :l | l verticalTree nodeDistance: 12; levelDistance: 30 ] ]
]

{ #category : 'class initialization' }
BeamModuleSourceCache class >> initialize [
	"I subscribe (idempotently) to the LanguageLink application
	 lifecycle so I can drop my per-module caches when the BEAM
	 bridge restarts.  Cached `BeamProxyObject`s become stale on
	 restart -- their `elixirVar` IDs reference the prior session's
	 `GtBridge.ObjectRegistry`, which is empty in the new session.

	 Pharo calls me automatically when the class is first defined
	 or the package is reloaded; for live patches via MCP
	 `defineMethod` we have to call me manually."
	LanguageLinkApplication announcer unsubscribe: self.
	LanguageLinkApplication announcer
		when: LanguageLinkStartAnnouncement
		send: #onApplicationStarted:
		to: self
]

{ #category : 'class initialization' }
BeamModuleSourceCache class >> liveCaches [
	"For testing / introspection — I return only the caches the GC
	 still considers reachable from outside.  After running
	 `Smalltalk garbageCollect` and dropping all consumer references,
	 dead entries clear from the WeakValueDictionary."
	caches ifNil: [ ^ #() ].
	^ caches values reject: [ :each | each isNil ]
]

{ #category : 'class initialization' }
BeamModuleSourceCache class >> onApplicationStarted: anAnnouncement [
	"Application (re)connected.  Clear every live cache instance's
	 state so stale proxies (from the prior session's
	 `GtBridge.ObjectRegistry`) don't survive into the new session.

	 Crucially I keep the registry intact so consumer references
	 (the `sourceCache` ivars on `ElixirModuleCoder` and
	 `ElixirFunctionExpanderAttribute`) remain valid, pointing at
	 the same instances they did before.  If I dropped the registry
	 instead, the next `for:` would build a fresh cache while the
	 old (orphaned) instance is still subscribed to the per-module
	 announcer -- both would process recompile events and consumers
	 would see every event twice.

	 The next consumer read finds an empty cache and falls back
	 through `ElixirModuleCoder>>functionEntries` to a bridge call
	 that returns fresh proxies."
	caches ifNil: [ ^ self ].
	caches valuesDo: [ :c | c ifNotNil: [ c clear ] ]
]

{ #category : 'class initialization' }
BeamModuleSourceCache class >> reset [
	"I drop the registry — image-wide rebuild.  Live caches held
	 elsewhere are NOT affected, only future lookups rebuild."
	caches := nil
]

{ #category : 'updating' }
BeamModuleSourceCache >> clear [
	"I drop my source map and entries list — useful for tests that
	 want to observe the side-effect of a fresh recompile on a
	 known-empty cache."
	sources := Dictionary new.
	entries := #()
]

{ #category : 'querying' }
BeamModuleSourceCache >> entries [
	"I return the full entries list from the most recent recompile,
	 in the order the BEAM emitted them.  Returns the empty Array if
	 no recompile event has populated me yet, OR if the cached
	 proxies have gone stale (BEAM restart clears
	 `GtBridge.ObjectRegistry` while my image-side cache survives,
	 so the proxies' `elixirVar` IDs point at registry slots that
	 no longer exist).  Consumers fall back to a fresh bridge
	 fetch via `coder functionEntries` in either case."
	entries isEmpty ifTrue: [ ^ entries ].
	(entries first attributeAt: #name) ifNil: [
		"Stale — clear so the next consumer read goes through the
		 bridge fallback and we don't render `nil/nil` rows."
		self clear.
		^ entries ].
	^ entries
]

{ #category : 'gt-views' }
BeamModuleSourceCache >> gtConsumersFor: aView [
	"I render every receiver currently subscribed to my per-module
	 announcer (excluding myself), grouped by their event class.
	 Useful for spotting which inspectors / coders / expanders are
	 currently looking at this module — and for catching accidental
	 retention as you close UI."

	<gtView>
	^ aView mondrian
		title: 'Consumers';
		priority: 5;
		painting: [ :aMondrian |
			| nodes edges labels colors announcer subscribers |
			nodes := OrderedCollection new.
			edges := OrderedCollection new.
			labels := IdentityDictionary new.
			colors := IdentityDictionary new.

			"Self at the centre."
			nodes add: self.
			labels at: self
				put: mod , ' (' , entries size asString , ' entries)'.
			colors at: self put: (Color fromHexString: '#e8f0fe').

			announcer := BeamEventAnnouncer for: mod.
			subscribers := [ announcer subscriptions subscriptions
				ifNil: [ #() ]
				ifNotNil: [ :subs | subs ] ]
				on: Error do: [ #() ].

			"Group external subscribers by event class then receiver class."
			(subscribers reject: [ :s | s subscriber == self ])
				do: [ :sub |
					| evt cls receiverGroup |
					evt := [ sub announcementClass ] on: Error do: [ nil ].
					cls := sub subscriber class.
					evt ifNotNil: [
						(nodes includes: evt) ifFalse: [
							nodes add: evt.
							labels at: evt put: evt name.
							colors at: evt put: (Color fromHexString: '#fff8d6').
							edges add: self -> evt ].
						receiverGroup := sub subscriber.
						(nodes includes: receiverGroup) ifFalse: [
							nodes add: receiverGroup.
							labels at: receiverGroup put: cls name.
							colors at: receiverGroup put: (Color gray alpha: 0.15) ].
						edges add: evt -> receiverGroup ] ].

			BeamMondrianHelpers
				paintLabeledGraphOn: aMondrian
				nodes: nodes edges: edges
				labels: labels colors: colors
				layout: [ :l | l verticalTree nodeDistance: 12; levelDistance: 30 ] ]
]

{ #category : 'accessing' }
BeamModuleSourceCache >> mod [
	^ mod
]

{ #category : 'accessing' }
BeamModuleSourceCache >> mod: aModuleName [
	mod := aModuleName.
	sources := Dictionary new.
	entries := #()
]

{ #category : 'subscriptions' }
BeamModuleSourceCache >> onBeamModuleRecompiled: anAnnouncement [
	"I update my source map and entries list from the announcement
	 payload, fan out narrow `BeamModuleSourceChanged` per
	 (function, arity) whose source changed, and fire one coarse
	 `BeamModuleEntriesUpdated` at the end so module-level consumers
	 (Source tab, streaming list) re-render exactly once per
	 recompile instead of N times for N changed functions.

	 Both events go to my per-module announcer, so subscribers
	 narrow to me already only receive events for my module."
	| functions |
	functions := anAnnouncement functions ifNil: [ ^ self ].
	(functions isKindOf: BeamProxyObject) ifTrue: [
		functions := functions asList ].
	entries := functions.
	functions do: [ :entry |
		| fnName arity newSource key |
		fnName := (entry attributeAt: #name) asString.
		arity := (entry attributeAt: #arity) asInteger.
		newSource := (entry attributeAt: #source) asString.
		key := { fnName. arity }.
		(sources at: key ifAbsent: [ nil ]) = newSource ifFalse: [
			sources at: key put: newSource.
			(BeamEventAnnouncer for: mod) announce:
				(BeamModuleSourceChanged
					mod: mod
					function: fnName
					arity: arity
					source: newSource) ] ].
	(BeamEventAnnouncer for: mod) announce:
		(BeamModuleEntriesUpdated mod: mod entries: entries)
]

{ #category : 'querying' }
BeamModuleSourceCache >> sourceForFunction: aName arity: anArity [
	"I return the cached source string for `aName/anArity` or nil if
	 the function hasn't been seen.  Consumers that get nil should
	 fall back to a bridge call (the cache is a memoization, not a
	 source-of-truth — a freshly-built cache hasn't seen any events
	 yet, so first reads always miss)."
	^ sources at: { aName asString. anArity } ifAbsent: [ nil ]
]

{ #category : 'accessing' }
BeamModuleSourceCache >> sources [
	"For testing / introspection.  Consumers should use
	 `sourceForFunction:arity:` instead."
	^ sources
]

{ #category : 'subscriptions' }
BeamModuleSourceCache >> subscribe [
	"I subscribe weakly to my module's announcer.  Weak means the
	 announcer holds a weak reference to me — it won't keep me
	 alive when no consumer does, so GC can collect me freely."
	(BeamEventAnnouncer for: mod) weak
		when: BeamModuleRecompiled
		send: #onBeamModuleRecompiled:
		to: self
]
