"
I announce that a BEAM module has been recompiled successfully and that any
GT surface displaying derived state for it should refresh.

I carry `sourceHash` so subscribers that already display the latest source can
short-circuit on equality.
"
Class {
	#name : 'BeamModuleRecompiled',
	#superclass : 'BeamModuleAnnouncement',
	#instVars : [ 'sourceHash' ],
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}

{ #category : 'instance creation' }
BeamModuleRecompiled class >> mod: aSymbol sourceHash: anIntegerOrNil [
	^ self new
		mod: aSymbol;
		sourceHash: anIntegerOrNil;
		yourself
]

{ #category : 'accessing' }
BeamModuleRecompiled >> sourceHash [
	^ sourceHash
]

{ #category : 'accessing' }
BeamModuleRecompiled >> sourceHash: anIntegerOrNil [
	sourceHash := anIntegerOrNil
]
