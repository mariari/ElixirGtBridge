Class {
	#name : 'BeamLinkCommandFactory',
	#superclass : 'LanguageLinkCommandFactory',
	#category : 'Gt4beam-Execution',
	#package : 'Gt4beam',
	#tag : 'Execution'
}

{ #category : 'initalization' }
BeamLinkCommandFactory >> setNotifyToInstruction: anInstruction [
	| trimmedSource parsed last |
	anInstruction ifNil: [ ^ anInstruction ].
	trimmedSource := SmaCCString on: anInstruction trimRight.
	parsed := ElixirParser parse: trimmedSource.
	last := parsed expressions expressions last.
	trimmedSource insert: ', command_id, port)' at: last stopPosition + 1.
	trimmedSource insert: 'GtBridge.Eval.notify(' at: last startPosition.
	^ trimmedSource asString
]
