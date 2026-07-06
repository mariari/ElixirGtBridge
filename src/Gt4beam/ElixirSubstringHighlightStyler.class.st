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
	"Empty when the coder's functionStreamingModel is nil (no filter bar, e.g. ALClassCoder)."

	| streaming |
	streaming := self attachedCoder ifNotNil: [ :c | c moduleCoder functionStreamingModel ].
	^ streaming ifNil: [ #(  ) ] ifNotNil: [ :s | s additionalFilters ]
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
