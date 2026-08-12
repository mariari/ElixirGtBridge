Class {
	#name : 'ElixirVariableOccurrenceStyler',
	#superclass : 'GtCoderAstStyler',
	#instVars : [
		'lastOccurrences',
		'lastVariables',
		'subscribedViewModel'
	],
	#category : 'Gt4beam-Styler',
	#package : 'Gt4beam',
	#tag : 'Styler'
}

{ #category : 'accessing' }
ElixirVariableOccurrenceStyler class >> highlightAttribute [
	^ BlTextHighlightAttribute new
		paint: BrGlamorousColors neutralBackgroundColor;
		yourself
]

{ #category : 'testing' }
ElixirVariableOccurrenceStyler class >> isVariableNode: aNode [
	"I hold for a bare identifier in value position. Call names, module
	 aliases and do-block keywords like `def` and `case` are identifiers
	 too, so the parent test is what tells them apart."

	^ ((aNode isKindOf: ElixirDotIdentifierNode)
		or: [ aNode isKindOf: ElixirDotDoIdentifierNode ])
			and: [ aNode parent isKindOf: ElixirSubMatchedExprNode ]
]

{ #category : 'accessing' }
ElixirVariableOccurrenceStyler class >> occurrencesAmong: aCollection forCursors: cursorPositions [
	"I answer the sorted ranges of every variable spelled like the one under
	 a cursor, that one included. Empty when no cursor is in a variable.
	 Matching is by name: Elixir source cannot say what binds without
	 expanding macros, so I do not pretend to know."

	| current |
	current := aCollection
		detect: [ :each |
			self
				range: (each startPosition to: each stopPosition)
				holdsCursor: cursorPositions ]
		ifNone: [ nil ].
	current ifNil: [ ^ #(  ) ].
	^ ((aCollection select: [ :each | each source = current source ])
		asSortedCollection: [ :a :b | a startPosition <= b startPosition ])
			collect: [ :each | each startPosition to: each stopPosition ]
]

{ #category : 'testing' }
ElixirVariableOccurrenceStyler class >> range: aRange holdsCursor: cursorPositions [
	"A cursor abutting either end of a word counts as being in it, and a Bl
	 cursor sits before the character at its position."

	^ cursorPositions anySatisfy: [ :each |
		each >= (aRange first - 1) and: [ each <= aRange last ] ]
]

{ #category : 'accessing' }
ElixirVariableOccurrenceStyler class >> variableNodesIn: anAst [
	"I answer every variable reference, in traversal order rather than
	 source order."

	| nodes |
	nodes := OrderedCollection new.
	anAst
		withAllNodesDo: [ :each |
			(self isVariableNode: each) ifTrue: [ nodes add: each ] ]
		andTokensDo: [ :each |  ].
	^ nodes
]

{ #category : 'accessing' }
ElixirVariableOccurrenceStyler >> coderViewModel: aCoderViewModel [
	"I follow my view model's cursor, since nothing in GT restyles when the
	 cursor moves. Focus skips the moved test, which would otherwise swallow
	 the restyle that clears my highlights when an editor is left."

	super coderViewModel: aCoderViewModel.
	subscribedViewModel == aCoderViewModel ifTrue: [ ^ self ].
	subscribedViewModel := aCoderViewModel.
	aCoderViewModel ifNil: [ ^ self ].
	aCoderViewModel weak
		when: GtTextualCoderViewModelCursorsChanged send: #onCursorMoved to: self;
		when: GtTextualCoderViewModelFocusChanged send: #requestRestyle to: self
]

{ #category : 'private' }
ElixirVariableOccurrenceStyler >> cursorPositions [
	^ self coderViewModel cursors positions
]

{ #category : 'private' }
ElixirVariableOccurrenceStyler >> cursorWithin: aCollection [
	| positions |
	positions := self cursorPositions.
	^ aCollection anySatisfy: [ :each |
		self class range: each holdsCursor: positions ]
]

{ #category : 'initialization' }
ElixirVariableOccurrenceStyler >> initialize [
	super initialize.
	lastOccurrences := #(  ).
	lastVariables := #(  )
]

{ #category : 'private' }
ElixirVariableOccurrenceStyler >> onCursorMoved [
	"I restyle only when what I would paint can have changed. The set I
	 painted is every occurrence in one definition, so a cursor still inside
	 it needs no work; nor does a cursor off every variable while nothing is
	 painted. I compare positions, so a cursor move costs no parsing."

	(self cursorWithin: lastOccurrences) ifTrue: [ ^ self ].
	((self cursorWithin: lastVariables) not and: [ lastOccurrences isEmpty ])
		ifTrue: [ ^ self ].
	self requestRestyle
]

{ #category : 'private' }
ElixirVariableOccurrenceStyler >> requestRestyle [
	"I reuse the cached AST. requestStyleSourceText would reset that cache
	 and reparse, which is too much work for a cursor move."

	| coder |
	coder := self coderViewModel ifNil: [ ^ self ] ifNotNil: [ :each | each coderModel ].
	coder announce: (GtCoderStyleTextRequest new coder: coder)
]

{ #category : 'styling' }
ElixirVariableOccurrenceStyler >> style: aText ast: theAst [
	"I give every occurrence of the variable under the cursor a grey
	 background. An unfocused editor keeps its cursors, so I paint nothing."

	| nodes |
	text := aText.
	lastOccurrences := #(  ).
	lastVariables := #(  ).
	self coderViewModel focused ifFalse: [ ^ self ].
	nodes := self class variableNodesIn: theAst.
	lastVariables := nodes collect: [ :each | each startPosition to: each stopPosition ].
	lastOccurrences := self class occurrencesAmong: nodes forCursors: self cursorPositions.
	lastOccurrences do: [ :each |
		self
			attribute: self class highlightAttribute
			from: each first
			to: each last ]
]
