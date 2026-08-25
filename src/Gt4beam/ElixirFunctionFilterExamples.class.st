"
I demonstrate the Functions-list filters' pure logic: kind
normalisation, substring matching, and the match/highlight agreement.
"
Class {
	#name : 'ElixirFunctionFilterExamples',
	#superclass : 'Object',
	#category : 'Gt4beam-Examples',
	#package : 'Gt4beam',
	#tag : 'Examples'
}

{ #category : 'examples' }
ElixirFunctionFilterExamples >> bodyFilterMatchesCaseInsensitively [
	"The Body filter finds a substring anywhere in the source,
	 regardless of case, like its Name sibling."

	<gtExample>
	| filter |
	filter := ElixirBodySubstringFilter forSubstring: 'MNESIA'.
	self assert: (filter matches: (self entryNamed: 'go' kind: 'def'
		source: 'def go, do: :mnesia.transaction(fn -> :ok end)')).
	self assert: (filter matches: (self entryNamed: 'go' kind: 'def'
		source: 'def go, do: :ets.lookup(:t, :k)')) not.
	^ filter
]

{ #category : 'support' }
ElixirFunctionFilterExamples >> entryNamed: aName kind: aKind source: aSource [
	^ BeamFunctionEntry fields: (Dictionary new
		at: 'name' put: aName;
		at: 'kind' put: aKind;
		at: 'source' put: aSource;
		yourself)
]

{ #category : 'examples' }
ElixirFunctionFilterExamples >> kindFilterNormalisesKindShapes [
	"The bridge sends kind as 'def'/'type' or #def/#type depending on
	 the eval path; entryKind: strips the # so one filter covers both."

	<gtExample>
	| filter |
	filter := ElixirKindFilter forKind: 'Types'.
	self assert: (filter matches: (self entryNamed: 't' kind: 'type' source: '@type t :: atom')).
	self assert: (filter matches: (self entryNamed: 't' kind: '#type' source: '@type t :: atom')).
	self assert: (filter matches: (self entryNamed: 'go' kind: 'def' source: 'def go, do: :ok')) not.
	^ filter
]

{ #category : 'examples' }
ElixirFunctionFilterExamples >> nameFilterHighlightAgreesWithMatch [
	"What matches is what lights up: an uppercase query matches a
	 lowercase name AND highlights it; the ranges index the original
	 string."

	<gtExample>
	| filter source ranges |
	filter := ElixirNameSubstringFilter forSubstring: 'GET'.
	self assert: (filter matches: (self entryNamed: 'get_user' kind: 'def'
		source: 'def get_user, do: :ok')).
	source := 'def get_user, do: forget()'.
	ranges := filter highlightRangesIn: source.
	self assert: ranges size equals: 2.
	ranges do: [ :r |
		self assert: (source copyFrom: r first to: r last) asLowercase equals: 'get' ].
	^ filter
]

{ #category : 'examples' }
ElixirFunctionFilterExamples >> visibilityFilterSeparatesExportedFromPrivate [
	"Exported keeps def, defmacro and public types; Private keeps the
	 p-suffixed kinds. All passes everything, like its Kind sibling."

	<gtExample>
	| exported private |
	exported := ElixirVisibilityFilter forVisibility: 'Exported'.
	private := ElixirVisibilityFilter forVisibility: 'Private'.
	#('def' 'defmacro' 'type' 'opaque') do: [ :kind |
		self assert: (exported matches: (self entryNamed: 'go' kind: kind source: '')).
		self assert: (private matches: (self entryNamed: 'go' kind: kind source: '')) not ].
	#('defp' 'defmacrop' 'typep') do: [ :kind |
		self assert: (exported matches: (self entryNamed: 'go' kind: kind source: '')) not.
		self assert: (private matches: (self entryNamed: 'go' kind: kind source: '')) ].
	self assert: ((ElixirVisibilityFilter forVisibility: 'All')
		matches: (self entryNamed: 'go' kind: 'defp' source: '')).
	^ exported
]
