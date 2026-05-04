"
I announce that disk for a BEAM module has new source bytes. Fires
from `HotReload.reload` after the file write, regardless of whether
the compile then succeeds or fails.

I carry the parsed function list so subscribers (caches, surfaces)
re-derive disk-truth state without a follow-up bridge call.

Future external file-watcher fires me too with the same payload
shape.
"
Class {
	#name : 'BeamModuleSourceWritten',
	#superclass : 'BeamModuleAnnouncement',
	#instVars : [
		'sourcePath',
		'source',
		'sourceHash',
		'functions'
	],
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}

{ #category : 'instance creation' }
BeamModuleSourceWritten class >> fromPayload: aPayload mod: aModuleName [
	"I build an announcement from the `source_written` portion of
	 `HotReload.reload`'s result. Module name comes from the caller
	 (the source-written portion only has bytes; the caller has the
	 module identity)."
	^ self new
		mod: aModuleName;
		sourcePath: (self payloadValue: #source_path from: aPayload);
		source: (self payloadValue: #source from: aPayload);
		sourceHash: (self payloadValue: #source_hash from: aPayload);
		functions: (self payloadValue: #functions from: aPayload);
		yourself
]

{ #category : 'private' }
BeamModuleSourceWritten class >> payloadValue: aKey from: aPayload [
	^ (aPayload respondsTo: #attributeAt:)
		ifTrue: [ aPayload attributeAt: aKey ]
		ifFalse: [ aPayload at: aKey ifAbsent: [ nil ] ]
]

{ #category : 'accessing' }
BeamModuleSourceWritten >> functions [
	^ functions
]

{ #category : 'accessing' }
BeamModuleSourceWritten >> functions: anArrayOrNil [
	functions := anArrayOrNil
]

{ #category : 'accessing' }
BeamModuleSourceWritten >> source [
	^ source
]

{ #category : 'accessing' }
BeamModuleSourceWritten >> source: aString [
	source := aString
]

{ #category : 'accessing' }
BeamModuleSourceWritten >> sourceHash [
	^ sourceHash
]

{ #category : 'accessing' }
BeamModuleSourceWritten >> sourceHash: anIntegerOrNil [
	sourceHash := anIntegerOrNil
]

{ #category : 'accessing' }
BeamModuleSourceWritten >> sourcePath [
	^ sourcePath
]

{ #category : 'accessing' }
BeamModuleSourceWritten >> sourcePath: aString [
	sourcePath := aString
]
