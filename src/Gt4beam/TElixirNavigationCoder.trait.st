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
	 Qualified calls navigate directly. Bare names delegate to browseImplementorsIn:."
	self
		detectElixirFunctionAt: aPosition
		ifFound: [ :moduleName :functionName |
			moduleName
				ifNotNil: [
					self
						navigateToQualified: moduleName
						function: functionName
						requesterObject: aRequester ]
				ifNil: [
					self browseImplementorsIn: functionName requesterObject: aRequester ] ]
		ifNone: [ ]
]

{ #category : 'navigation' }
TElixirNavigationCoder >> browseImplementorsIn: aString requesterObject: aRequester [
	"I find implementors of the selected text as a function name.
	 If exactly one implementor exists, I jump straight to its docs;
	 otherwise I spawn a search filter."
	| name reply results |
	name := aString trimBoth.
	reply := self application evaluateAndWait:
		'GtBridge.Analysis.implementors(:', name, ')'.
	(reply isKindOf: BeamBridgeEvalError) ifTrue: [ ^ self ].
	results := reply asList.
	results size = 1
		ifTrue: [
			| only |
			only := results first.
			self
				notifyObjectSpawn: (self application evaluateAndWait:
					(self
						functionDocsQueryFor: (only attributeAt: #module) asString
						name: name
						arity: (only attributeAt: #arity)))
				requesterObject: aRequester ]
		ifFalse: [
			self
				notifyObjectSpawn: (ElixirSearchFilter new
					title: name, ' implementors'
					items: results
					application: self application)
				requesterObject: aRequester ]
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

{ #category : 'navigation - private' }
TElixirNavigationCoder >> functionDocsQueryFor: aResolvedModule function: aFunctionName [
	"I look up aFunctionName's arity in aResolvedModule and return
	 the BEAM expression that fetches docs for that specific function.
	 If no matching function exists, I fall back to module-level docs."
	| fns match |
	fns := (self application evaluateAndWait:
		'GtBridge.Analysis.all_functions(', aResolvedModule, ')') asList.
	match := fns detect: [ :f | (f attributeAt: #name) asString = aFunctionName ]
		ifNone: [ ^ self moduleDocsQuery: aResolvedModule ].
	^ self
		functionDocsQueryFor: aResolvedModule
		name: aFunctionName
		arity: (match attributeAt: #arity)
]

{ #category : 'navigation - private' }
TElixirNavigationCoder >> functionDocsQueryFor: aResolvedModule name: aFunctionName arity: anArity [
	"I return the BEAM expression that fetches docs for one function."
	^ 'GtBridge.Documentation.for_function(', aResolvedModule,
		', :', aFunctionName,
		', ', anArity asString, ')'
]

{ #category : 'shortcuts' }
TElixirNavigationCoder >> initializeNavigationShortcuts: addOns [
	"I register C-m (implementors) and C-n (references)."
	addOns addShortcut: GtSourceCoderBrowseImplementorsShortcut new.
	addOns addShortcut: GtSourceCoderBrowseReferencesShortcut new
]

{ #category : 'navigation - private' }
TElixirNavigationCoder >> moduleDocsQuery: aResolvedModule [
	"I return the BEAM expression that fetches docs for an entire module."
	^ 'GtBridge.Documentation.for_module(', aResolvedModule, ')'
]

{ #category : 'navigation - private' }
TElixirNavigationCoder >> navigateToQualified: moduleName function: functionName requesterObject: aRequester [
	"I resolve the module alias and spawn a documentation object
	 for the specific function (or the module if the function
	 lookup fails). Used by C-m on qualified calls."
	| resolved query |
	resolved := self resolveModuleName: moduleName.
	query := [ self functionDocsQueryFor: resolved function: functionName ]
		on: Error do: [ self moduleDocsQuery: resolved ].
	self
		notifyObjectSpawn: (self application evaluateAndWait: query)
		requesterObject: aRequester
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
