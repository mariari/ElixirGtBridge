Class {
	#name : 'ElixirFunctionExpanderStyler',
	#superclass : 'GtCoderAstStyler',
	#instVars : [
		'application',
		'cachedAstHash',
		'cachedAst',
		'lastIndex',
		'cachedModuleAliasesFor',
		'cachedModuleAliases'
	],
	#category : 'Gt4beam',
	#package : 'Gt4beam'
}

{ #category : 'accessing' }
ElixirFunctionExpanderStyler >> application [
	^ application ifNil: [
		application := BeamLinkApplication uniqueInstance ]
]

{ #category : 'accessing' }
ElixirFunctionExpanderStyler >> application: anApp [
	application := anApp
]

{ #category : 'styling' }
ElixirFunctionExpanderStyler >> attachWrenchesIn: aText source: source defmoduleHeads: skip aliasNodes: aliasNodes aliasMap: aliasMap resolution: resolution [
	"Outermost alias outside any defmodule head is a wrench candidate.
	 Build entries (1 per single, N per grouped), batch-resolve unknown
	 names against the bridge, then attach for the unresolved."
	| candidates entries |
	candidates := self outermostAliasesIn:
		(aliasNodes reject: [ :n | self node: n insideAnyOf: skip ]).
	entries := candidates flatCollect: [ :n |
		self wrenchEntriesFor: n source: source aliasMap: aliasMap ].
	self
		learnClassificationsFor: (entries collect: [ :e | e at: #resolved ]) asSet
		on: resolution.
	entries do: [ :e | self attachWrenchEntry: e in: aText resolution: resolution ]
]

{ #category : 'accessing' }
ElixirFunctionExpanderStyler >> contextModuleName [
	"I return the module name from the coder. Every Elixir coder that
	 attaches me — GtElixirCoderModel, ElixirModuleCoder,
	 ElixirFunctionCoder — implements #contextModuleName."
	^ self coderViewModel ifNotNil: [ :vm |
		vm coderModel ifNotNil: [ :coder | coder contextModuleName ] ]
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> addDefmoduleHeadFor: node source: source into: heads [
	"Add the alias being *defined* by `defmodule X` / `defprotocol X`
	 so the wrench skips it."
	| ident call identSrc |
	ident := node identifier ifNil: [ ^ self ].
	call := node call ifNil: [ ^ self ].
	identSrc := source copyFrom: ident startPosition to: ident stopPosition.
	(#('defmodule' 'defprotocol') includes: identSrc) ifFalse: [ ^ self ].
	call expressions ifNotEmpty: [ heads add: call expressions first ]
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> parsedAstFor: source [
	"Cached SmaCC parse — keyed on source hash so cursor moves /
	 focus changes don't re-parse a multi-thousand-line file."
	| hash ast |
	hash := source hash.
	hash = cachedAstHash ifTrue: [ ^ cachedAst ].
	ast := [ ElixirParser parseStream: source readStream ]
		on: Error do: [ nil ].
	cachedAstHash := hash.
	cachedAst := ast.
	^ ast
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> callSiteFor: aParensCall aliasMap: aliasMap source: source resolution: resolution [
	| dotIdent fnToken expr resolved isLocal arity |
	dotIdent := self dotParenIdentifierOf: aParensCall identifier.
	dotIdent ifNil: [ ^ nil ].
	fnToken := dotIdent identifier ifNil: [ ^ nil ].
	expr := dotIdent expression.
	isLocal := expr isNil.
	isLocal
		ifTrue: [ resolved := self contextModuleName ]
		ifFalse: [
			resolved := self
				resolveAlias: (source copyFrom: expr startPosition to: expr stopPosition)
				with: aliasMap ].
	resolved ifNil: [ ^ nil ].
	(isLocal or: [ (resolution classify: resolved) = #resolved ])
		ifFalse: [ ^ nil ].
	arity := self arityFor: aParensCall.
	(self isPipedCall: aParensCall) ifTrue: [ arity := arity + 1 ].
	^ Dictionary new
		at: #target_module put: resolved;
		at: #function put: fnToken value;
		at: #arity put: arity;
		at: #fnEndPosition put: fnToken stopPosition;
		yourself
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> isPipedCall: aParensCall [
	"True if I'm the RHS of `|>` — the BEAM bumps arity by 1."
	| grandparent |
	grandparent := aParensCall parent ifNotNil: [ :p | p parent ].
	^ (grandparent isKindOf: ElixirMatchedOpExprNode)
		and: [ grandparent op value = '|>' ]
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> extractAliasesFrom: source [
	"I parse `alias` directives line-by-line and return a Dictionary
	 mapping the short name to the fully qualified module name.

	 Three forms:
	   alias Foo.Bar.Baz             ->  Baz -> Foo.Bar.Baz
	   alias Foo.Bar.Baz, as: Z      ->  Z   -> Foo.Bar.Baz
	   alias Foo.Bar.{X, Y, Z}       ->  X   -> Foo.Bar.X
	                                     Y   -> Foo.Bar.Y
	                                     Z   -> Foo.Bar.Z

	 Without me, every locally-aliased identifier (e.g. `Text` for
	 `GtBridge.Phlow.Text`) shows up as an unresolved module and the
	 styler attaches a wrench.  With me, the styler classifies the
	 RESOLVED full name instead, so the wrench only fires when the
	 module truly isn't loaded."
	| aliases |
	aliases := Dictionary new.
	source lines do: [ :rawLine |
		| line body |
		line := rawLine trimBoth.
		(line beginsWith: 'alias ') ifTrue: [
			body := (line copyFrom: 7 to: line size) trimBoth.
			(body includes: ${)
				ifTrue: [ self parseGroupedAlias: body into: aliases ]
				ifFalse: [ self parseSingleAlias: body into: aliases ] ] ].
	^ aliases
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> groupedAliasEntriesFor: aNode in: source [
	"I expand a grouped-alias DotAlias node (whose source span is
	 `Foo.{A, B, C}`) into per-name entries suitable for wrench
	 attachment.  Returns OrderedCollection of associations
	 `fullModuleName -> absoluteEndPositionInSource`, one per
	 individual name inside the braces.

	 Without me, the AST walker treats the whole `Foo.{A, B, C}`
	 literal as a single module reference and offers to create that
	 verbatim string -- which isn't a real module.  With me, each
	 name resolves to its canonical full form (`Foo.A`, `Foo.B`,
	 `Foo.C`) and gets its own wrench."
	| absStart nodeSrc |
	absStart := aNode startPosition.
	nodeSrc := source copyFrom: aNode startPosition to: aNode stopPosition.
	^ (self parseGroupedAliasBody: nodeSrc) collect: [ :assoc |
		assoc key -> (absStart + assoc value - 1) ]
]

{ #category : 'initialization' }
ElixirFunctionExpanderStyler >> initialize [
	super initialize.
	lastIndex := 0
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> moduleAliasesFor: aModuleName [
	"I return the surrounding module's `alias` declarations as an
	 `OrderedCollection` of `{short. full}` pairs.  Bridge-cached
	 per styler instance, keyed on the module name -- module aliases
	 rarely change, and the styler runs on every keystroke.

	 Returns empty on bridge error or if the module has no aliases."
	cachedModuleAliasesFor = aModuleName ifTrue: [ ^ cachedModuleAliases ].
	cachedModuleAliasesFor := aModuleName.
	cachedModuleAliases := [
		(self application evaluateAndWait:
			'GtBridge.Analysis.module_aliases(', aModuleName, ')')
				asList collect: [ :proxyPair |
					| items |
					items := proxyPair asList.
					{ items first asString. items second asString } ] ]
		on: Error do: [ #() ].
	^ cachedModuleAliases
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> nextIndex [
	^ lastIndex := lastIndex + 1
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> outermostAliasesIn: aCollection [
	"I return the outermost ElixirDotAliasNodes from `aCollection`,
	 dropping every node whose span is strictly contained in
	 another.  Sort + single-pass O(n log n) — DotAliasNodes don't
	 overlap (only nest or are disjoint), so once the current
	 outermost ends, any later node with start > its stop is the
	 next outermost."
	| sorted outermost outerStop |
	sorted := aCollection asSortedCollection: [ :a :b |
		a startPosition < b startPosition
			or: [ a startPosition = b startPosition
				and: [ a stopPosition > b stopPosition ] ] ].
	outermost := OrderedCollection new.
	outerStop := 0.
	sorted do: [ :node |
		node startPosition > outerStop ifTrue: [
			outermost add: node.
			outerStop := node stopPosition ] ].
	^ outermost
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> parseGroupedAlias: body into: aliases [
	"I parse `Foo.Bar.{A, B, C}` and emit per-name entries."
	(self parseGroupedAliasBody: body) do: [ :assoc |
		| full short |
		full := assoc key.
		short := (full substrings: '.') last.
		aliases at: short put: full ]
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> parseGroupedAliasBody: body [
	"I parse a grouped alias body of the form `Foo.Bar.{A, B, C}`
	 and return an OrderedCollection of associations
	 `fullName -> endPositionInBody`, where the end position is the
	 1-based index of the LAST character of each short name within
	 `body`.  Returns an empty collection if the body is malformed
	 or has no prefix.

	 Both the alias-map extractor (which discards positions) and the
	 grouped-wrench expander (which needs them to attach wrenches at
	 each individual name) go through me."
	| openIdx closeIdx prefix result nameStart i ch endRel name |
	openIdx := body indexOf: ${.
	closeIdx := body indexOf: $} startingAt: openIdx.
	(openIdx > 1 and: [ closeIdx > openIdx ]) ifFalse: [ ^ #() ].
	prefix := (body copyFrom: 1 to: openIdx - 2) trimBoth.
	prefix isEmpty ifTrue: [ ^ #() ].
	result := OrderedCollection new.
	nameStart := nil.
	i := openIdx + 1.
	[ i <= closeIdx ] whileTrue: [
		ch := body at: i.
		(ch = $, or: [ ch = $} ])
			ifTrue: [
				nameStart ifNotNil: [
					name := (body copyFrom: nameStart to: i - 1) trimBoth.
					name isEmpty ifFalse: [
						endRel := i - 1.
						[ endRel >= nameStart and: [ (body at: endRel) isSeparator ] ]
							whileTrue: [ endRel := endRel - 1 ].
						result add: prefix , '.' , name -> endRel ] ].
				nameStart := nil ]
			ifFalse: [
				ch isSeparator ifFalse: [
					nameStart ifNil: [ nameStart := i ] ] ].
		i := i + 1 ].
	^ result
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> parseSingleAlias: body into: aliases [
	"I parse `Foo.Bar.Baz` (short defaults to last segment) and
	 `Foo.Bar.Baz, as: Z` (short = Z) forms."
	| asIdx |
	asIdx := body indexOfSubCollection: ', as: '.
	asIdx > 0
		ifTrue: [
			| full short |
			full := (body copyFrom: 1 to: asIdx - 1) trimBoth.
			short := (body copyFrom: asIdx + 6 to: body size) trimBoth.
			(full isEmpty or: [ short isEmpty ]) ifFalse: [
				aliases at: short put: full ] ]
		ifFalse: [
			| full short |
			full := body trimBoth.
			(full isEmpty or: [ full includes: $  ]) ifFalse: [
				short := (full substrings: '.') last.
				aliases at: short put: full ] ]
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> resolveAlias: aName with: anAliasMap [
	"I expand `aName` through the alias map.  If the head segment
	 (before the first dot) is a key in the map, replace it with the
	 mapped full name.  Otherwise return `aName` unchanged.

	 Examples (with map { 'Text' -> 'GtBridge.Phlow.Text' }):
	   'Text'            ->  'GtBridge.Phlow.Text'
	   'Text.Inner'      ->  'GtBridge.Phlow.Text.Inner'
	   'NotAnAlias.Foo'  ->  'NotAnAlias.Foo'  (unchanged)"
	| segments head tail resolved |
	segments := aName substrings: '.'.
	head := segments first.
	resolved := anAliasMap at: head ifAbsent: [ ^ aName ].
	tail := segments allButFirst.
	tail isEmpty ifTrue: [ ^ resolved ].
	^ String streamContents: [ :s |
		s nextPutAll: resolved.
		tail do: [ :seg | s nextPut: $.; nextPutAll: seg ] ]
]

{ #category : 'styling' }
ElixirFunctionExpanderStyler >> style: aText ast: theAst [
	"One AST walk feeds two passes: wrench affordances on unresolved
	 module aliases and |> expanders on resolved Mod.fun calls."
	| source ast heads aliases parensCalls aliasMap resolution |
	text := aText.
	lastIndex := 0.
	source := aText asString.
	source size < 10 ifTrue: [ ^ self ].
	ast := self parsedAstFor: source.
	ast ifNil: [ ^ self ].
	heads := IdentitySet new.
	aliases := OrderedCollection new.
	parensCalls := OrderedCollection new.
	ast withAllNodesDo: [ :node |
		(node isKindOf: ElixirDotAliasNode) ifTrue: [ aliases add: node ].
		node class == ElixirParensCallNode ifTrue: [ parensCalls add: node ].
		(node isKindOf: ElixirBlockExprNode) ifTrue: [
			self addDefmoduleHeadFor: node source: source into: heads ] ].
	aliasMap := self aliasMapFor: source.
	resolution := BeamModuleResolution default.
	self
		attachWrenchesIn: aText source: source
		defmoduleHeads: heads aliasNodes: aliases
		aliasMap: aliasMap resolution: resolution.
	self
		attachExpandersIn: aText source: source
		parensCalls: parensCalls
		aliasMap: aliasMap resolution: resolution
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> aliasMapFor: source [
	"Source-level `alias` directives, merged with the surrounding
	 module's aliases (when a context module is known).  Source wins
	 on conflict — the user's local `alias` line takes precedence."
	| aliasMap |
	aliasMap := self extractAliasesFrom: source.
	self contextModuleName ifNotNil: [ :mod |
		(self moduleAliasesFor: mod) do: [ :pair |
			aliasMap at: pair first ifAbsentPut: [ pair second ] ] ].
	^ aliasMap
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> arityFor: aParensCall [
	"Zero for `Mod.fun()` (parser models the empty parens with a nil
	 args slot); arg count for `Mod.fun(a, b, ...)`."
	^ (aParensCall call ifNotNil: [ :c | c args ifNotNil: [ :a | a args ] ])
		ifNotNil: [ :a | a size ] ifNil: [ 0 ]
]

{ #category : 'styling' }
ElixirFunctionExpanderStyler >> attachExpandersIn: aText source: source parensCalls: parensCalls aliasMap: aliasMap resolution: resolution [
	"Attach a |> expander after every Mod.fun call whose target
	 resolves to a loaded module."
	parensCalls do: [ :n |
		(self
			callSiteFor: n
			aliasMap: aliasMap
			source: source
			resolution: resolution) ifNotNil: [ :site |
				self attachExpanderFor: site in: aText ] ]
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> attachExpanderFor: site in: aText [
	"Attach a single expander attribute at the function's end position."
	| endPos attr |
	endPos := site at: #fnEndPosition.
	endPos > aText size ifTrue: [ ^ self ].
	attr := ElixirFunctionExpanderAttribute new
		targetModule: (site at: #target_module)
		functionName: (site at: #function)
		arity: (site at: #arity)
		application: self application.
	attr id: ('elixir-expander--' , self nextIndex asString) asSymbol.
	self attribute: attr from: endPos to: endPos
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> attachWrenchEntry: entry in: aText resolution: resolution [
	"Attach a wrench attribute if the entry's resolved name is
	 known-unresolved by the cache."
	| endPos resolved |
	resolved := entry at: #resolved.
	(resolution classify: resolved) = #unresolved ifFalse: [ ^ self ].
	endPos := entry at: #endPosition.
	endPos > aText size ifTrue: [ ^ self ].
	self
		attribute: (ElixirUnknownModuleAttribute
			forModule: resolved
			application: self application)
		from: endPos to: endPos
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> dotParenIdentifierOf: identifier [
	"Return the inner ElixirDotParenIdentifierNode for a `Mod.fun`
	 call shape, nil otherwise."
	identifier class == ElixirDotCallIdentifierNode ifFalse: [ ^ nil ].
	^ identifier identifier class == ElixirDotParenIdentifierNode
		ifTrue: [ identifier identifier ]
		ifFalse: [ nil ]
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> learnClassificationsFor: names on: resolution [
	"Resolve any `names` the cache doesn't already know via one
	 batch bridge call; record each as resolved/unresolved so
	 subsequent classify: calls answer locally."
	| unknowns res resolved unresolved |
	unknowns := names select: [ :n | (resolution classify: n) = #unknown ].
	unknowns isEmpty ifTrue: [ ^ self ].
	res := [ self application evaluateAndWait:
		'GtBridge.Analysis.modules_loaded?(' , (self listExprFor: unknowns) , ')' ]
		on: Error do: [ ^ self ].
	res ifNil: [ ^ self ].
	resolved := OrderedCollection new.
	unresolved := OrderedCollection new.
	unknowns do: [ :name |
		| loaded |
		loaded := [ res attributeAt: name ] on: Error do: [ nil ].
		loaded == true ifTrue: [ resolved add: name ].
		loaded == false ifTrue: [ unresolved add: name ] ].
	resolution recordResolved: resolved unresolved: unresolved
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> listExprFor: names [
	"Render `names` as an Elixir list literal of double-quoted strings."
	^ String streamContents: [ :s |
		s nextPutAll: '['.
		names asArray
			do: [ :n | s nextPut: $"; nextPutAll: n; nextPut: $" ]
			separatedBy: [ s nextPutAll: ', ' ].
		s nextPutAll: ']' ]
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> node: aNode insideAnyOf: heads [
	"True if `aNode` IS a defmodule head or sits inside one's span.
	 Both cases must skip — the literal head, and bare prefix children
	 that survive 'outermost' filtering once their parent is removed."
	^ heads anySatisfy: [ :h |
		aNode == h or: [
			aNode startPosition >= h startPosition
				and: [ aNode stopPosition <= h stopPosition ] ] ]
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> wrenchEntriesFor: aliasNode source: source aliasMap: aliasMap [
	"Each outermost DotAlias node yields one or more wrench entries.
	 Grouped literals `Foo.{A, B}` yield one entry per inner name;
	 single literals yield one entry."
	| nodeSrc |
	nodeSrc := source copyFrom: aliasNode startPosition to: aliasNode stopPosition.
	(nodeSrc includes: ${)
		ifTrue: [
			^ (self groupedAliasEntriesFor: aliasNode in: source) collect: [ :assoc |
				self
					wrenchEntryName: assoc key
					resolvedAs: assoc key
					endingAt: assoc value ] ].
	^ Array with: (self
		wrenchEntryName: nodeSrc
		resolvedAs: (self resolveAlias: nodeSrc with: aliasMap)
		endingAt: aliasNode stopPosition)
]

{ #category : 'private' }
ElixirFunctionExpanderStyler >> wrenchEntryName: name resolvedAs: resolvedName endingAt: endPosition [
	^ Dictionary new
		at: #name put: name;
		at: #resolved put: resolvedName;
		at: #endPosition put: endPosition;
		yourself
]
