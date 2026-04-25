Trait {
	#name : 'TElixirNavigationCoder',
	#category : 'Gt4beam',
	#package : 'Gt4beam'
}

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
	 (which is wrong for pipes, captures, and macro-generated calls)."
	self
		detectElixirFunctionAt: aPosition
		ifFound: [ :moduleName :functionName |
			moduleName
				ifNotNil: [
					self
						browseImplementorsInModule: (self resolveModuleName: moduleName)
						function: functionName
						requesterObject: aRequester ]
				ifNil: [
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
	 Qualified calls query directly. Bare names use context module."
	self
		detectElixirFunctionAt: aPosition
		ifFound: [ :moduleName :functionName |
			| resolved |
			resolved := moduleName
				ifNil: [ self contextModuleName ]
				ifNotNil: [ self resolveModuleName: moduleName ].
			resolved ifNil: [ ^ self ].
			self browseReferencesIn: resolved, '.', functionName
				requesterObject: aRequester ]
		ifNone: [ ]
]

{ #category : 'navigation' }
TElixirNavigationCoder >> browseReferencesIn: aString requesterObject: aRequester [
	"I find references to the selected function name."
	| parts moduleName functionName reply results |
	parts := aString trimBoth splitOn: '.'.
	parts size < 2 ifTrue: [ ^ self ].
	moduleName := (parts copyFrom: 1 to: parts size - 1) joinUsing: '.'.
	functionName := parts last.
	reply := self application evaluateAndWait:
		'GtBridge.Analysis.function_references(',
		moduleName, ', :', functionName, ')'.
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
