"
I announce that a BEAM module has been recompiled successfully and that any
GT surface displaying derived state for it should refresh.

I carry the new derived state inline whenever the BEAM produced it:

- `sourceHash` — equality short-circuit for subscribers that already
  display the latest source.
- `functions` — the new function entry list (Array of Dictionaries
  with `name`, `arity`, `source`, `start`, `end_line`, ...) or nil
  for sibling modules.  Subscribers handle nil by bridge-calling.

The directly-saved module always carries `functions`; sibling
modules recompiled by ParallelCompiler propagation arrive bare and
let subscribers refetch on demand.  This is the FRP shape the bridge
is moving toward — broadcast carries the new value, not just the
fact of the event.
"
Class {
	#name : 'BeamModuleRecompiled',
	#superclass : 'BeamModuleAnnouncement',
	#instVars : [
		'sourceHash',
		'functions'
	],
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}

{ #category : 'instance creation' }
BeamModuleRecompiled class >> fromPayload: aPayload [
	"I build an announcement from the dict shape returned by
	 GtBridge.HotReload.reload — `mod`, `source_hash`, and
	 `functions` keys. Missing keys leave the corresponding slot nil;
	 subscribers handle nil by bridge-calling.

	 Accepts either a Smalltalk Dictionary (used by unit-style tests)
	 or a BeamProxyObject wrapping an Elixir map (the production path
	 from hot_reload's recompiled list)."
	^ self new
		mod: (self payloadValue: #mod from: aPayload);
		sourceHash: (self payloadValue: #source_hash from: aPayload);
		functions: (self payloadValue: #functions from: aPayload);
		yourself
]

{ #category : 'instance creation' }
BeamModuleRecompiled class >> mod: aSymbol sourceHash: anIntegerOrNil [
	^ self new
		mod: aSymbol;
		sourceHash: anIntegerOrNil;
		yourself
]

{ #category : 'accessing' }
BeamModuleRecompiled >> functions [
	"I return the new function entries for the recompiled module
	 (Array of Dictionaries with `name`, `arity`, `source`, `start`,
	 `end_line`, ...) or nil if not carried (sibling modules)."
	^ functions
]

{ #category : 'accessing' }
BeamModuleRecompiled >> functions: anArrayOrNil [
	functions := anArrayOrNil
]

{ #category : 'accessing' }
BeamModuleRecompiled >> sourceHash [
	^ sourceHash
]

{ #category : 'accessing' }
BeamModuleRecompiled >> sourceHash: anIntegerOrNil [
	sourceHash := anIntegerOrNil
]
