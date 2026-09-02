Class {
	#name : 'ElixirVariableOccurrenceStylerExamples',
	#superclass : 'Object',
	#category : 'Gt4beam-Examples',
	#package : 'Gt4beam',
	#tag : 'Examples'
}

{ #category : 'fixtures' }
ElixirVariableOccurrenceStylerExamples >> definitionSource [
	"I spell statement in two functions, at 67 and 91 in one and 174 and
	 188 in the other."

	^ 'defmodule Foo do
  def stage(a) do
    case run(a) do
      {:ok, statement, _t} -> {:ok, statement}
    end
  end

  def final_stage(b) do
    case stage(b) do
      {:ok, statement} -> statement
    end
  end
end'
]

{ #category : 'fixtures' }
ElixirVariableOccurrenceStylerExamples >> moduleSource [
	"I spell baz, total and n as variables, and defmodule, def, case and
	 @attr as identifiers that are not."

	^ 'defmodule Foo do
  @attr 1
  def bar(baz) do
    total = baz
    case total do
      n -> n * baz
    end
  end
end'
]

{ #category : 'fixtures' }
ElixirVariableOccurrenceStylerExamples >> occurrencesIn: aString at: aPosition [
	"I answer the start positions a cursor would highlight."

	| ast |
	ast := ElixirParser parseWithErrors: aString.
	^ ((ElixirVariableOccurrenceStyler
		occurrencesAmong: (ElixirVariableOccurrenceStyler variableNodesIn: ast)
		forCursors: { aPosition }) collect: [ :each | each first ]) asArray
]

{ #category : 'fixtures' }
ElixirVariableOccurrenceStylerExamples >> source [
	"I spell x as a variable four times, at 1, 23, 32 and 44, and three
	 more times as something else."

	^ 'x = 1
IO.puts("x is #{x}")
foo(x, :x)
%{x: x}'
]

{ #category : 'examples' }
ElixirVariableOccurrenceStylerExamples >> keywordsAndAttributesAreNotVariables [
	"`def` and `case` parse as identifiers too, and only their position in
	 the tree tells them apart. That same position keeps the scrutinee of
	 `case total do` in, which its own node class would have lost."

	<gtExample>
	| names |
	names := (ElixirVariableOccurrenceStyler
		variableNodesIn: (ElixirParser parseWithErrors: self moduleSource))
			collect: [ :each | each source ].
	self
		assert: names asArray
		equals: #( 'baz' 'total' 'baz' 'total' 'n' 'baz' 'n' ).
	^ names
]

{ #category : 'examples' }
ElixirVariableOccurrenceStylerExamples >> matchingIsByNameAndNotByBinding [
	"Two functions spelling a variable the same read as one. Telling them
	 apart means knowing what binds, which Elixir source does not say until
	 macros are expanded, so I match names and claim nothing more."

	<gtExample>
	| starts |
	starts := self occurrencesIn: self definitionSource at: 67.
	self assert: starts equals: #( 67 91 174 188 ).
	^ starts
]

{ #category : 'examples' }
ElixirVariableOccurrenceStylerExamples >> movingWithinThePaintedSetDoesNoWork [
	"I ask for a restyle only when what I would paint can differ. Another
	 occurrence of the same variable is already painted, so it costs
	 nothing; leaving every variable has to repaint, to clear."

	<gtExample>
	| src coder viewModel editor requests move |
	src := self definitionSource.
	coder := GtElixirCoderModel new.
	coder currentSourceString: src.
	viewModel := coder asCoderViewModel.
	viewModel stylers: { ElixirVariableOccurrenceStyler new }.
	viewModel focused: true.
	editor := BrTextEditor new.
	editor text: src asRopedText.
	requests := OrderedCollection new.
	move := [ :position |
		editor moveCursorTo: position.
		viewModel cursors: editor cursors from: nil ].
	move value: 67.
	viewModel compositeStyler style: coder currentSourceText copy.
	coder announcer
		when: GtCoderStyleTextRequest
		do: [ :each | requests add: each ]
		for: requests.
	move value: 174.
	self assert: requests size equals: 0.
	move value: 3.
	self assert: requests size equals: 1.
	^ requests
]

{ #category : 'examples' }
ElixirVariableOccurrenceStylerExamples >> occurrencesAreEmptyOffAVariable [
	"A cursor in whitespace highlights nothing."

	<gtExample>
	| starts |
	starts := self occurrencesIn: self source at: 2.
	self assert: starts isEmpty.
	^ starts
]

{ #category : 'examples' }
ElixirVariableOccurrenceStylerExamples >> occurrencesSkipAtomsAndKeys [
	"A cursor on the first x finds all four variables, including the one
	 inside the interpolation, and neither the atom :x, the map key x: nor
	 the literal text. A cursor at either edge of the word counts."

	<gtExample>
	| starts |
	starts := self occurrencesIn: self source at: 1.
	self assert: starts equals: #( 1 23 32 44 ).
	self assert: (self occurrencesIn: self source at: 0) equals: #( 1 23 32 44 ).
	^ starts
]
