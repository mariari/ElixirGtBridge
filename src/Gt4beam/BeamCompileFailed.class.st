"
I announce that a save attempt for a BEAM module did not produce new code.

I carry `errors` — a list of compile error payloads (file, line, column,
message) — for surfaces that show inline error markers (the radical-save
inline error sliver, future global error panels, etc.).

Cache reapers and surface-refresh subscribers should NOT subscribe to me:
nothing changed in BEAM module state, so no derived state needs invalidation.
"
Class {
	#name : 'BeamCompileFailed',
	#superclass : 'BeamModuleAnnouncement',
	#instVars : [
		'errors'
	],
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}

{ #category : 'instance creation' }
BeamCompileFailed class >> mod: aSymbolOrNil errors: aListOfErrors [
	^ self new
		mod: aSymbolOrNil;
		errors: aListOfErrors;
		yourself
]

{ #category : 'accessing' }
BeamCompileFailed >> errors [
	^ errors
]

{ #category : 'accessing' }
BeamCompileFailed >> errors: aListOfErrors [
	errors := aListOfErrors
]
