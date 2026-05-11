Class {
	#name : 'ElixirCoderFormatShortcut',
	#superclass : 'GtSourceCoderShortcut',
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'accessing' }
ElixirCoderFormatShortcut >> description [
	^ 'Format the buffer through Code.format_string!'
]

{ #category : 'initialization' }
ElixirCoderFormatShortcut >> initialize [
	super initialize.
	combination := BlKeyCombination primaryShiftF
]

{ #category : 'accessing' }
ElixirCoderFormatShortcut >> name [
	^ 'Format'
]

{ #category : 'action' }
ElixirCoderFormatShortcut >> performOnEditor: aBrTextEditor element: aBrEditorElement coderViewModel: aSourceCoderViewModel dueTo: aShortcutEvent [
	"I format the current buffer text through `Code.format_string!`
	 and replace the editor's source with the result.  Smalltalk
	 text uses CR; Elixir's parser rejects CR, so normalise to LF
	 first."
	| coder source application normalized encoded expr formatted |
	coder := aSourceCoderViewModel coderModel.
	application := coder application.
	application ifNil: [ ^ self ].
	source := aBrTextEditor text asString.
	normalized := (source copyReplaceAll: String crlf with: String lf)
		copyReplaceAll: String cr with: String lf.
	encoded := normalized utf8Encoded base64Encoded.
	expr := 'IO.iodata_to_binary(Code.format_string!(Base.decode64!("',
		encoded, '")))'.
	formatted := [ application evaluateAndWait: expr ]
		on: Error do: [ :e | nil ].
	"Use `sourceText:from:synchronously:` rather than rebuilding
	 `coder sourceCode:` — the former updates only the current text
	 (keeping the saved disk baseline so `isModified` stays correct)
	 and fires the change events that re-run the stylers, so colours
	 refresh without waiting for the next keypress."
	formatted ifNotNil: [
		aSourceCoderViewModel
			sourceText: formatted asString asRopedText
			from: self
			synchronously: true ]
]
