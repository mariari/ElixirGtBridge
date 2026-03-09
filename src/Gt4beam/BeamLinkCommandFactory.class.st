Class {
	#name : #BeamLinkCommandFactory,
	#superclass : #LanguageLinkCommandFactory,
	#category : #'Gt4beam-Execution'
}

{ #category : #initalization }
BeamLinkCommandFactory >> setNotifyToInstruction: anInstruction [
	| trimmedSource parsed last |
	trimmedSource := SmaCCString on: anInstruction trimRight.
	parsed := ElixirParser parse: trimmedSource.
	last := parsed expressions expressions last.
	trimmedSource insert: '), command_id, port)' at: last stopPosition + 1.
	trimmedSource insert: 'Eval.notify((' at: last startPosition.
	^ trimmedSource asString
]
