"
I announce a successful BEAM recompile and carry the new derived state
inline: `functions` and the whole-file `source`.  The
directly-saved module carries all three; sibling modules from
ParallelCompiler propagation arrive bare and let subscribers refetch.
"
Class {
	#name : 'BeamModuleRecompiled',
	#superclass : 'BeamModuleAnnouncement',
	#instVars : [
		'functions',
		'source'
	],
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}

{ #category : 'instance creation' }
BeamModuleRecompiled class >> fromPayload: aPayload [
	^ self new
		mod: (self payloadValue: #mod from: aPayload);
		functions: (self payloadValue: #functions from: aPayload);
		source: (self payloadValue: #source from: aPayload);
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
BeamModuleRecompiled >> source [
	"Whole-file source, or nil for sibling modules."
	^ source ifNotNil: [ :s | s asString ]
]

{ #category : 'accessing' }
BeamModuleRecompiled >> source: aStringOrNil [
	source := aStringOrNil
]

