"
I announce that a module's full function-entries list has been
refreshed in the local cache.

I am the *coarse* sibling of `BeamModuleSourceChanged`: where the
narrow event fires per-function whose source actually changed, I
fire ONCE per recompile, after all per-function events.  This
lets module-level consumers (the Source tab rebuilder, the
function streaming list) re-render once per recompile instead of
N times for N changed functions.

The cache (`BeamModuleSourceCache`) is the sole publisher.

### Public API

- `mod` — module name string (e.g. 'GtBridge.Eval')
- `entries` — the full entries list as received from the
  recompile payload (one map/proxy per function/type).
"
Class {
	#name : 'BeamModuleEntriesUpdated',
	#superclass : 'BeamModuleAnnouncement',
	#instVars : [
		'entries'
	],
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}

{ #category : 'instance creation' }
BeamModuleEntriesUpdated class >> mod: aModName entries: anEntriesList [
	^ self new
		mod: aModName;
		entries: anEntriesList;
		yourself
]

{ #category : 'accessing' }
BeamModuleEntriesUpdated >> entries [
	^ entries
]

{ #category : 'accessing' }
BeamModuleEntriesUpdated >> entries: anEntriesList [
	entries := anEntriesList
]
