"
I announce that a function's source within a module has been
updated in the local cache.

I am the *narrow* event that consumers subscribe to instead of
subscribing to `BeamModuleRecompiled` directly.  The cache
(`BeamModuleSourceCache`) is the sole subscriber to the recompile
event for a given module; on receipt it updates its internal
source map and fires me — one announcement per (module, function,
arity) pair whose source actually changed.

This is the FRP shape from `project_wrench_design_frp_alignment`:
one writer (the cache) per derivation, many readers (expanders,
function coders) that just subscribe to me and read from the cache.

### Public API

- `mod` — module name string (e.g. 'GtBridge.Eval')
- `function` — function name string
- `arity` — non-negative integer
- `source` — the new source text
"
Class {
	#name : 'BeamModuleSourceChanged',
	#superclass : 'BeamModuleAnnouncement',
	#instVars : [
		'function',
		'arity',
		'source'
	],
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}

{ #category : 'instance creation' }
BeamModuleSourceChanged class >> mod: aModName function: aFunName arity: anArity source: aSource [
	^ self new
		mod: aModName;
		function: aFunName;
		arity: anArity;
		source: aSource;
		yourself
]

{ #category : 'accessing' }
BeamModuleSourceChanged >> arity [
	^ arity
]

{ #category : 'accessing' }
BeamModuleSourceChanged >> arity: anInteger [
	arity := anInteger
]

{ #category : 'accessing' }
BeamModuleSourceChanged >> function [
	^ function
]

{ #category : 'accessing' }
BeamModuleSourceChanged >> function: aString [
	function := aString
]

{ #category : 'accessing' }
BeamModuleSourceChanged >> source [
	^ source
]

{ #category : 'accessing' }
BeamModuleSourceChanged >> source: aString [
	source := aString
]
