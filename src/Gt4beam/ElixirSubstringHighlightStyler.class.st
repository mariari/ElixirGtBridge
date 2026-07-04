Class {
	#name : 'ElixirSubstringHighlightStyler',
	#superclass : 'GtCoderAstStyler',
	#category : 'Gt4beam-Styler',
	#package : 'Gt4beam',
	#tag : 'Styler'
}

{ #category : 'accessing' }
ElixirSubstringHighlightStyler class >> highlightAttribute [
	^ BlTextDecorationAttribute new
		underline;
		color: BrGlamorousColors textHighlightColor;
		yourself
]

{ #category : 'accessing' }
ElixirSubstringHighlightStyler >> activeFilters [
	"The filters currently applied to the function list, empty when unattached."

	| coder streaming |
	coder := self attachedCoder.
	coder isNil ifTrue: [ ^ #() ].
	streaming := coder moduleCoder functionStreamingModel.
	^ streaming isNil ifTrue: [ #() ] ifFalse: [ streaming additionalFilters ]
]

{ #category : 'accessing' }
ElixirSubstringHighlightStyler >> attachedCoder [
	^ self coderViewModel ifNotNil: [ :vm | vm coderModel ]
]

{ #category : 'styling' }
ElixirSubstringHighlightStyler >> style: aText ast: theAst [
	"Underline the source ranges each active filter asks to highlight."

	| attr source |
	text := aText.
	source := aText asString.
	attr := self class highlightAttribute.
	self activeFilters
		do: [ :filter | 
			(filter highlightRangesIn: source)
				do: [ :range | 
					self
						attribute: attr
						from: range first
						to: range last ] ]
]
