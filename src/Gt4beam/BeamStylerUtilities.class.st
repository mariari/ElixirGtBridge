Class {
	#name : 'BeamStylerUtilities',
	#superclass : 'Object',
	#category : 'Gt4beam',
	#package : 'Gt4beam'
}

{ #category : '*Gt4beam' }
BeamStylerUtilities class >> colorAndHighlightParenthesesLeft: aLeftIndex right: aRightIndex atNestingLevel: aNestingLevel inText: aText leftLength: aLength [
	self
		highlightParenthesesLeft: aLeftIndex
		right: aRightIndex
		inText: aText.
	self
		colorParenthesesLeft: aLeftIndex
		right: aRightIndex
		atNestingLevel: aNestingLevel
		inText: aText
		leftLength: aLength
]

{ #category : '*Gt4beam' }
BeamStylerUtilities class >> colorParenthesesLeft: aLeftIndex right: aRightIndex atNestingLevel: aNestingLevel inText: aText leftLength: aLength [
	| color |
	color := self parenthesesColorAt: aNestingLevel.
	(aText from: aLeftIndex to: aLeftIndex + aLength) foreground: color.
	(aText from: aRightIndex to: aRightIndex) foreground: color
]

{ #category : '*Gt4beam' }
BeamStylerUtilities class >> highlightParenthesesLeft: aLeftIndex right: aRightIndex inText: aText [
	| theParanthesesMarker cursorEnterAction cursorLeaveAction |
	theParanthesesMarker := BrTextInvisibleMarkerAttribute new.
	aText
		attribute: theParanthesesMarker
		from: aLeftIndex
		to: aRightIndex.

	cursorEnterAction := [ :aTextEditor | 
		aTextEditor text
			findAttribute: theParanthesesMarker
			indicesDo: [ :aParanthesesStart :aParanthesesEnd | 
				aTextEditor text
					attribute: (GtPharoParenthesesHighlightAttribute
							paint: BrGlamorousColors neutralBackgroundColor)
					from: aParanthesesStart
					to: aParanthesesEnd ] ].

	cursorLeaveAction := [ :aTextEditor | 
		aTextEditor text
			findAttribute: theParanthesesMarker
			indicesDo: [ :aParanthesesStart :aParanthesesEnd | 
				(aTextEditor text from: aParanthesesStart to: aParanthesesEnd)
					clearAttributesOfClass: GtPharoParenthesesHighlightAttribute ] ].

	(aText from: aLeftIndex to: aLeftIndex)
		onCursorEnter: cursorEnterAction
		leave: cursorLeaveAction.

	(aText from: aRightIndex to: aRightIndex)
		onCursorEnter: cursorEnterAction
		leave: cursorLeaveAction
]

{ #category : '*Gt4beam' }
BeamStylerUtilities class >> keywords [
	^ {'defmodule'.
		'def'.
		'defview'.
		'defmacro'.
		'defp'.
		'defexample'.
		'use'.
		'alias'.
		'typedstruct'.
		'do'.
		'end'}
]

{ #category : '*Gt4beam' }
BeamStylerUtilities class >> parenthesesColorAt: anIndex [
	| colors |
	colors := self parenthesesColors.
	^ colors at: (anIndex - 1) \\ colors size + 1
]

{ #category : '*Gt4beam' }
BeamStylerUtilities class >> parenthesesColors [
	| colors |
	colors := BrGlamorousColors distinctTenStrongColors allButFirst allButLast
			collect: [ :each | each twiceDarker ].
	^ colors
]
