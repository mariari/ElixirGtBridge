"
I demonstrate the Functions-up-to range: namespace ancestors, the
filter's dropdown, and the concatenated entry stream.
"
Class {
	#name : 'ElixirFunctionsUpToExamples',
	#superclass : 'Object',
	#category : 'Gt4beam-Examples',
	#package : 'Gt4beam',
	#tag : 'Examples'
}

{ #category : 'examples' }
ElixirFunctionsUpToExamples >> ancestorsAreNearestFirst [
	"A nested module's ancestors are its name prefixes, nearest first; a
	 top-level module has none."

	<gtExample>
	| ancestors |
	ancestors := ElixirModuleCoder namespaceAncestorsOf: 'Zkfol.Lang.Statement'.
	self assert: ancestors equals: #('Zkfol.Lang' 'Zkfol').
	self assert: (ElixirModuleCoder namespaceAncestorsOf: 'Zkfol') equals: #().
	^ ancestors
]

{ #category : 'examples' }
ElixirFunctionsUpToExamples >> rangeIsMostSpecificFirstWithImportsAfterTheirImporter [
	"Own module, then each ancestor up to the chosen one, each followed by
	 its imports. Resolution is primed so no bridge is needed."

	<gtExample>
	| coder range |
	BeamModuleResolution default
		recordResolved: #('Up.Mid' 'Up' 'Up.Shared')
		unresolved: #().
	coder := self coderNamed: 'Up.Mid.Leaf' imports: #().
	(coder relatedCoderFor: 'Up.Mid') cachedImports: #('Up.Shared').
	(coder relatedCoderFor: 'Up') cachedImports: #().
	range := (coder coderRangeUpTo: 'Up') collect: [ :each | each moduleName ].
	self assert: range asArray equals: #('Up.Mid.Leaf' 'Up.Mid' 'Up.Shared' 'Up').
	^ range
]

{ #category : 'examples' }
ElixirFunctionsUpToExamples >> rangeStopsAtTheChosenAncestor [
	"Choosing the module itself yields a range of one: even with imports
	 primed, the bare default stays just the module — imports join only
	 when the range widens to an ancestor."

	<gtExample>
	| coder range |
	BeamModuleResolution default recordResolved: #('Up.Mid' 'Up' 'Up.Shared') unresolved: #().
	coder := self coderNamed: 'Up.Mid.Leaf' imports: #('Up.Shared').
	range := (coder coderRangeUpTo: 'Up.Mid.Leaf') collect: [ :each | each moduleName ].
	self assert: range asArray equals: #('Up.Mid.Leaf').
	^ range
]

{ #category : 'examples' }
ElixirFunctionsUpToExamples >> dropdownListsTheModuleFirstAndSelected [
	"Like Pharo's Methods-up-to: the module itself is the first, default
	 entry; ancestors follow nearest first."

	<gtExample>
	| model items |
	BeamModuleResolution default recordResolved: #('Up.Mid' 'Up') unresolved: #().
	model := ElixirFunctionsUpToFilter filterDescriptor2For:
		(ElixirFunctionStreamingModel new moduleCoder: (self coderNamed: 'Up.Mid.Leaf' imports: #())).
	items := (model items value) collect: #itemValue.
	self assert: items asArray equals: #('Up.Mid.Leaf' 'Up.Mid' 'Up').
	self assert: model selectedItem itemValue equals: 'Up.Mid.Leaf'.
	self assert: model name equals: 'Functions up to'.
	^ model
]

{ #category : 'examples' }
ElixirFunctionsUpToExamples >> upToFilterNeverNarrowsEntries [
	"The filter only names the range; narrowing is left to its siblings."

	<gtExample>
	| filter |
	filter := ElixirFunctionsUpToFilter forModule: 'Up'.
	self assert: (filter matches: (BeamFunctionEntry fields: (Dictionary new at: 'name' put: 'go'; yourself))).
	self assert: filter filterValueString equals: 'Up'.
	^ filter
]

{ #category : 'support' }
ElixirFunctionsUpToExamples >> coderNamed: aName imports: anArray [
	"A module coder with no bridge; imports are pre-seeded."
	^ ElixirModuleCoder new
		moduleName: aName;
		cachedImports: anArray;
		yourself
]

{ #category : 'support' }
ElixirFunctionsUpToExamples >> primeEntriesFor: aModuleName names: anArray [
	"Fill a module's source cache the way a recompile event would."
	(BeamModuleSourceCache for: aModuleName) applyEntries: (anArray collect: [ :each |
		Dictionary new
			at: 'name' put: each; at: 'arity' put: 0; at: 'kind' put: 'def';
			at: 'start' put: 1; at: 'end_line' put: 1; at: 'source' put: 'def ', each, ', do: :ok';
			yourself ])
]

{ #category : 'support' }
ElixirFunctionsUpToExamples >> streamingModelUpTo: aModuleName [
	"A Leaf-under-Up model whose range is chosen by the filter."
	| coder model |
	BeamModuleResolution default recordResolved: #('Up.Mid' 'Up') unresolved: #().
	self primeEntriesFor: 'Up.Mid.Leaf' names: #('leaf_a' 'leaf_b').
	self primeEntriesFor: 'Up.Mid' names: #('mid_a').
	self primeEntriesFor: 'Up' names: #('leaf_a').
	coder := self coderNamed: 'Up.Mid.Leaf' imports: #().
	(coder relatedCoderFor: 'Up.Mid') cachedImports: #().
	(coder relatedCoderFor: 'Up') cachedImports: #().
	model := ElixirFunctionStreamingModel new moduleCoder: coder.
	model additionalFilters: { ElixirFunctionsUpToFilter forModule: aModuleName }.
	^ model
]

{ #category : 'examples' }
ElixirFunctionsUpToExamples >> streamConcatenatesTheRangeMostSpecificFirst [
	"Own entries first, then the parent's, then the grandparent's, each
	 tagged with its module."

	<gtExample>
	| entries |
	entries := (self streamingModelUpTo: 'Up') rangeEntries.
	self
		assert: (entries collect: [ :e | (e attributeAt: #module), '.', (e attributeAt: #name) ]) asArray
		equals: #('Up.Mid.Leaf.leaf_a' 'Up.Mid.Leaf.leaf_b' 'Up.Mid.mid_a' 'Up.leaf_a').
	^ entries
]

{ #category : 'examples' }
ElixirFunctionsUpToExamples >> cacheKeysTellSameNamedFunctionsApart [
	"leaf_a/0 exists in Leaf and in Up; the key carries the module."

	<gtExample>
	| model keys |
	model := self streamingModelUpTo: 'Up'.
	keys := model rangeEntries collect: [ :e | model newCoderCacheKeyFor: e ].
	self assert: keys asSet size equals: keys size.
	self assert: keys first equals: 'Up.Mid.Leaf.leaf_a/0'.
	^ keys
]

{ #category : 'examples' }
ElixirFunctionsUpToExamples >> foreignRowsCrumbAndCannotMove [
	"A parent's function shows the module crumb, saves through the
	 parent's coder, and has no list to move within."

	<gtExample>
	| model own foreign |
	model := self streamingModelUpTo: 'Up'.
	own := model newCoderFor: model rangeEntries first.
	foreign := model newCoderFor: model rangeEntries last.
	self assert: own showsModuleInHeader not.
	self assert: own list == model.
	self assert: foreign showsModuleInHeader.
	self assert: foreign list isNil.
	self assert: foreign moduleCoder moduleName equals: 'Up'.
	self assert: foreign moduleCoder functionStreamingModel == model.
	^ foreign
]

{ #category : 'examples' }
ElixirFunctionsUpToExamples >> newFunctionTargetsAreTheWritableRangeOwnFirst [
	"Only modules with a local source file can take a new function;
	 the module itself comes first."

	<gtExample>
	| model coder targets |
	model := self streamingModelUpTo: 'Up'.
	coder := model moduleCoder.
	coder functionStreamingModel: model.
	coder sourcePath: '/tmp/leaf.ex'. '/tmp/leaf.ex' asFileReference ensureCreateFile.
	(coder relatedCoderFor: 'Up') sourcePath: '/tmp/up.ex'. '/tmp/up.ex' asFileReference ensureCreateFile.
	targets := coder writableRangeCoders collect: [ :each | each moduleName ].
	self assert: targets asArray equals: #('Up.Mid.Leaf' 'Up').
	^ targets
]
