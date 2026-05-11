"
I announce that disk for a BEAM module has new source bytes. Fires
from `HotReload.reload` after the file write, regardless of whether
the compile then succeeds or fails.

I carry the parsed function list so subscribers (caches, surfaces)
re-derive disk-truth state without a follow-up bridge call.
"
Class {
	#name : 'BeamModuleSourceWritten',
	#superclass : 'BeamModuleAnnouncement',
	#instVars : [
		'functions'
	],
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}

{ #category : 'instance creation' }
BeamModuleSourceWritten class >> fromPayload: aPayload mod: aModuleName [
	^ self new
		mod: aModuleName;
		functions: (self payloadValue: #functions from: aPayload);
		yourself
]

{ #category : 'accessing' }
BeamModuleSourceWritten >> functions [
	^ functions
]

{ #category : 'accessing' }
BeamModuleSourceWritten >> functions: anArrayOrNil [
	functions := anArrayOrNil
]
