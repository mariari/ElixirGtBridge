Class {
	#name : 'ElixirFunctionExpanderAttribute',
	#superclass : 'BrGlamorousTriangleExpanderTextAttribute',
	#instVars : [
		'targetModule',
		'functionName',
		'arity',
		'application'
	],
	#category : 'Gt4beam-Styler',
	#package : 'Gt4beam',
	#tag : 'Styler'
}

{ #category : 'building' }
ElixirFunctionExpanderAttribute >> buildExpandedElement [
	"ElixirFunctionCoder owns save/refresh, has no Move (no list injected) and no
	 generic eval buttons.  functionEntries bridge-evals all_functions when there is
	 no readable local source, so stdlib / no-source functions still render their
	 synth entry (@spec + no-source comment) instead of collapsing to a bare header."
	| path mc entry |
	path := application evaluateAndWait: 'GtBridge.Resolve.source_file(', targetModule, ')'.
	mc := ElixirModuleCoder new
		moduleName: targetModule;
		application: application;
		sourcePath: ((path isString and: [ path asFileReference exists ])
			ifTrue: [ path ] ifFalse: [ nil ]).
	entry := self resolvedEntryIn: mc functionEntries.
	entry ifNil: [ ^ self buildHeader ].
	^ BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ];
		margin: (BlInsets top: 3 left: 10 bottom: 3 right: 10);
		addChild: self buildHeader;
		addChild: (ElixirFunctionCoder forEntry: entry moduleCoder: mc) asCoderViewModel asElement
]

{ #category : 'private' }
ElixirFunctionExpanderAttribute >> buildHeader [
	"I return the same breadcrumb header the filter rows use, so
	 |> inline expansions and Module > function/arity rows look
	 and click identically.  The 'Create module' wrench moved out
	 of here onto `ElixirUnknownModuleAttribute`, attached inline
	 by the styler at the unknown identifier itself — that's the
	 placement that actually reaches unresolved references (the
	 |> expander only renders for resolvable calls)."
	^ ElixirFunctionCoderHeaderElement
		forModule: targetModule
		functionName: functionName
		arity: arity
		application: application
]

{ #category : 'initialization' }
ElixirFunctionExpanderAttribute >> initialize [
	super initialize.
	self attributesCreatingBlock: [
		BrTextAdornmentDynamicAttribute new
			beAppend;
			stencil: [ self buildExpandedElement ] ]
]

{ #category : 'printing' }
ElixirFunctionExpanderAttribute >> printOn: aStream [
	aStream
		nextPutAll: 'elixir-expander: ';
		nextPutAll: targetModule asString;
		nextPut: $.;
		nextPutAll: functionName asString
]

{ #category : 'private' }
ElixirFunctionExpanderAttribute >> resolvedEntryIn: entries [
	"I pick the entry to expand: the exact def when it has source; a
	 default-arg head resolves to the def that generates it; an arity
	 that exists nowhere (mid-edit) resolves to the nearest greater
	 def; a source-less export with no covering def keeps its
	 synthesized stub."
	| exact candidates |
	exact := entries
		detect: [ :e | (e attributeAt: #name) asString = functionName asString
			and: [ (e attributeAt: #arity) = arity ] ]
		ifNone: [ nil ].
	(exact isNotNil and: [ (exact attributeAt: #start) > 0 ]) ifTrue: [ ^ exact ].
	candidates := (entries select: [ :e |
		(e attributeAt: #name) asString = functionName asString
			and: [ ((e attributeAt: #kind) asString beginsWith: 'def')
			and: [ (e attributeAt: #arity) > arity
			and: [ (e attributeAt: #start) > 0 ] ] ] ])
		asSortedCollection: [ :x :y | (x attributeAt: #arity) < (y attributeAt: #arity) ].
	candidates do: [ :c |
		arity >= ((c attributeAt: #arity) - ((c attributeAt: #defaults) ifNil: [ 0 ]))
			ifTrue: [ ^ c ] ].
	exact ifNotNil: [ ^ exact ].
	^ candidates isEmpty ifTrue: [ nil ] ifFalse: [ candidates first ]
]

{ #category : 'accessing' }
ElixirFunctionExpanderAttribute >> targetModule: mod functionName: fn arity: ar application: app [
	"I record my target's identity; the function coder I build owns its
	 own recompile refresh, so I no longer subscribe to module events."
	targetModule := mod.
	functionName := fn.
	arity := ar.
	application := app
]
