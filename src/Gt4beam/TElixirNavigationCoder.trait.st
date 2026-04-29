Trait {
	#name : 'TElixirNavigationCoder',
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam'
}

{ #category : 'context menu' }
TElixirNavigationCoder >> addNavigationContextMenuAddOns: ignoredAst to: coderAddOns [
	"I surface Browse implementors (C-m) and Browse references (C-n)
	 in the right-click menu so users can discover the shortcuts
	 instead of having to know them up front -- mirrors the
	 Smalltalk source coder's Navigation group.

	 The shortcut objects already dispatch to my
	 `browseImplementorsAt:requesterObject:` and
	 `browseReferencesAt:requesterObject:` methods on activation, so
	 registering them via `addContextMenuItemFrom:group:withId:to:`
	 reuses that machinery -- the menu entry, the keyboard shortcut,
	 and the bridge call all share one definition.

	 Lives on the trait so every coder that mixes
	 `TElixirNavigationCoder` (the snippet coder, the per-function
	 coder used by the Meta browser's Functions tab, etc.) picks it
	 up via trait composition.

	 Guarded on `self application` since the navigation actions need
	 a live BEAM bridge to dispatch to."
	<gtCoderContextMenuAddOns>
	self application ifNil: [ ^ self ].
	(self
		addContextMenuItemFrom: GtSourceCoderBrowseImplementorsShortcut new
		group: BrMenuItemGroupConfiguration navigation
		withId: nil
		to: coderAddOns) ifNotNil: [ :anAction | anAction priority: 10 ].
	(self
		addContextMenuItemFrom: GtSourceCoderBrowseReferencesShortcut new
		group: BrMenuItemGroupConfiguration navigation
		withId: nil
		to: coderAddOns) ifNotNil: [ :anAction | anAction priority: 11 ]
]

{ #category : 'requirements' }
TElixirNavigationCoder >> application [
	"I return the BeamLinkApplication used for BEAM evaluation.
	 Required from the composing coder hierarchy."
	^ self explicitRequirement
]

{ #category : 'navigation' }
TElixirNavigationCoder >> browseImplementorsAt: aPosition requesterObject: aRequester [
	"I find implementors of the Elixir function at cursor position.
	 Both qualified and bare-name calls spawn a search filter — the
	 user picks the right arity. Avoids guessing arity from the AST
	 (which is wrong for pipes, captures, and macro-generated calls).

	 A non-uppercase prefix (`builder.text(...)`, `&1.inserted_at`) is
	 a runtime variable / capture-arg reference, not a module. We
	 can't know statically which module the function lives in, so
	 fall back to bare-name search across every module."
	self
		detectElixirFunctionAt: aPosition
		ifFound: [ :moduleName :functionName |
			| looksLikeModule |
			looksLikeModule := moduleName notNil
				and: [ moduleName isNotEmpty
				and: [ moduleName first isLetter
				and: [ moduleName first isUppercase ] ] ].
			looksLikeModule
				ifTrue: [
					self
						browseImplementorsInModule: (self resolveModuleName: moduleName)
						function: functionName
						requesterObject: aRequester ]
				ifFalse: [
					self browseImplementorsIn: functionName requesterObject: aRequester ] ]
		ifNone: [ ]
]

{ #category : 'navigation' }
TElixirNavigationCoder >> browseImplementorsIn: aString requesterObject: aRequester [
	"I find implementors of the selected text as a function name and
	 spawn a search filter. Always uses the filter so the user can
	 pick across modules and arities — no implicit single-result jump."
	| name reply results |
	name := aString trimBoth.
	reply := self application evaluateAndWait:
		'GtBridge.Analysis.implementors(:', name, ')'.
	(reply isKindOf: BeamBridgeEvalError) ifTrue: [ ^ self ].
	results := reply asList.
	self
		notifyObjectSpawn: (ElixirSearchFilter new
			title: name, ' implementors'
			items: results
			application: self application)
		requesterObject: aRequester
]

{ #category : 'navigation' }
TElixirNavigationCoder >> browseImplementorsInModule: aResolvedModule function: aFunctionName requesterObject: aRequester [
	"I spawn a filter showing all functions named aFunctionName in
	 aResolvedModule (any arity). Used for qualified C-m so the user
	 picks the right arity instead of us guessing from the AST."
	| reply results |
	reply := self application evaluateAndWait:
		'GtBridge.Analysis.all_functions(', aResolvedModule, ')',
		' |> Enum.filter(& &1.name == "', aFunctionName, '")',
		' |> Enum.map(&Map.put(&1, :module, "', aResolvedModule, '"))'.
	(reply isKindOf: BeamBridgeEvalError) ifTrue: [ ^ self ].
	results := reply asList.
	self notifyObjectSpawn:
		(ElixirSearchFilter new
			title: aResolvedModule, '.', aFunctionName
			items: results
			application: self application)
		requesterObject: aRequester
]

{ #category : 'navigation' }
TElixirNavigationCoder >> browseReferencesAt: aPosition requesterObject: aRequester [
	"I find references to the Elixir function at cursor position.
	 A real module qualifier (uppercase, like `Foo.bar`) restricts
	 references to that module's function.  Anything else —
	 variable refs (`builder.text(...)`), capture-arg field access
	 (`&1.inserted_at`), bare names imported from Kernel (`elem`),
	 or bare names not defined in the context module — falls back
	 to references-by-name across all modules via
	 browseReferencesIn: with a bare name (no dot).  Bare names that
	 ARE defined in the context module use the context module so
	 results stay focused."
	self
		detectElixirFunctionAt: aPosition
		ifFound: [ :moduleName :functionName |
			| target looksLikeModule |
			looksLikeModule := moduleName notNil
				and: [ moduleName isNotEmpty
				and: [ moduleName first isLetter
				and: [ moduleName first isUppercase ] ] ].
			target := looksLikeModule
				ifTrue: [ (self resolveModuleName: moduleName), '.', functionName ]
				ifFalse: [
					(moduleName isNil and: [ self functionInContext: functionName ])
						ifTrue: [ self contextModuleName, '.', functionName ]
						ifFalse: [ functionName ] ].
			self browseReferencesIn: target requesterObject: aRequester ]
		ifNone: [ ]
]

{ #category : 'navigation' }
TElixirNavigationCoder >> browseReferencesIn: aString requesterObject: aRequester [
	"I find references to the selected function name. A qualified
	 string (Module.fn) restricts to that module; a bare name
	 (no dot) queries references to that name across all modules
	 — used as the fallback when we can't statically determine
	 the target (variable refs, Kernel/imported calls, etc.)."
	| parts moduleArg functionName reply results trimmed |
	trimmed := aString trimBoth.
	parts := trimmed splitOn: '.'.
	parts size < 2
		ifTrue: [
			moduleArg := 'nil'.
			functionName := parts first ]
		ifFalse: [
			moduleArg := (parts copyFrom: 1 to: parts size - 1) joinUsing: '.'.
			functionName := parts last ].
	reply := self application evaluateAndWait:
		'GtBridge.Analysis.function_references(',
		moduleArg, ', :', functionName, ')'.
	(reply isKindOf: BeamBridgeEvalError) ifTrue: [ ^ self ].
	results := reply asList.
	self notifyObjectSpawn:
		(ElixirSearchFilter new
			title: aString trimBoth, ' references'
			items: results
			application: self application)
		requesterObject: aRequester
]

{ #category : 'navigation' }
TElixirNavigationCoder >> contextModuleName [
	"I return the module name being edited, or nil.
	 Users override to provide module context."
	^ nil
]

{ #category : 'requirements' }
TElixirNavigationCoder >> currentSourceString [
	"I return the current source as a String.
	 Required from the composing coder hierarchy."
	^ self explicitRequirement
]

{ #category : 'navigation' }
TElixirNavigationCoder >> detectElixirFunctionAt: aPosition ifFound: foundBlock ifNone: noneBlock [
	"I detect the Elixir function reference at cursor position.
	 For 'Module.function' I yield moduleName and functionName.
	 For bare 'function' I yield nil module and functionName."
	| source wordStart wordEnd token dotPos moduleName functionName |
	source := self currentSourceString.
	(aPosition < 1 or: [ aPosition > source size ]) ifTrue: [ ^ noneBlock value ].
	wordStart := aPosition.
	[ wordStart > 1 and: [
		| c | c := source at: wordStart - 1.
		c isLetter or: [ c isDigit or: [ '_.' includes: c ] ] ] ]
		whileTrue: [ wordStart := wordStart - 1 ].
	wordEnd := aPosition.
	[ wordEnd < source size and: [
		| c | c := source at: wordEnd + 1.
		c isLetter or: [ c isDigit or: [ '_?!' includes: c ] ] ] ]
		whileTrue: [ wordEnd := wordEnd + 1 ].
	token := source copyFrom: wordStart to: wordEnd.
	token ifEmpty: [ ^ noneBlock value ].
	dotPos := token lastIndexOf: $..
	dotPos > 0
		ifTrue: [
			moduleName := token copyFrom: 1 to: dotPos - 1.
			functionName := token copyFrom: dotPos + 1 to: token size ]
		ifFalse: [
			moduleName := nil.
			functionName := token ].
	(functionName isEmpty or: [ functionName first isUppercase ])
		ifTrue: [ ^ noneBlock value ].
	^ foundBlock value: moduleName value: functionName
]

{ #category : 'navigation' }
TElixirNavigationCoder >> functionInContext: aFunctionName [
	"I am true when the bare function name is defined in the current
	 context module. Used to decide whether C-n on an unqualified call
	 should query references-in-context or fall back to bare-name
	 implementors search across all modules."
	| ctx reply |
	ctx := self contextModuleName.
	ctx ifNil: [ ^ false ].
	reply := [ self application evaluateAndWait:
		'GtBridge.Analysis.function_in_module?(', ctx, ', "', aFunctionName, '")' ]
		on: Error do: [ ^ false ].
	(reply isKindOf: BeamBridgeEvalError) ifTrue: [ ^ false ].
	^ reply == true
]

{ #category : 'shortcuts' }
TElixirNavigationCoder >> initializeNavigationShortcuts: addOns [
	"I register C-m (implementors) and C-n (references)."
	addOns addShortcut: GtSourceCoderBrowseImplementorsShortcut new.
	addOns addShortcut: GtSourceCoderBrowseReferencesShortcut new
]

{ #category : 'requirements' }
TElixirNavigationCoder >> notifyObjectSpawn: anObject requesterObject: aRequester [
	"I announce the spawn so GT's inspector / requester chain
	 can render the result. Required from the composing coder hierarchy."
	^ self explicitRequirement
]

{ #category : 'navigation' }
TElixirNavigationCoder >> resolveModuleName: aName [
	"I resolve a possibly-aliased module name using the current
	 module context. Returns the fully qualified name."
	| ctx |
	ctx := self contextModuleName.
	ctx ifNil: [ ^ aName ].
	^ [ (self application evaluateAndWait:
		'GtBridge.Analysis.resolve_alias(', ctx, ', "', aName, '")') ]
		on: Error do: [ aName ]
]
