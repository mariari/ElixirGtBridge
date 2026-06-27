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
	"I return a breadcrumb header + the function snippet for my target.
	 ElixirFunctionCoder owns save (splice via spliceFunction:) and its own
	 recompile refresh; no list is injected so it has no Move; and being a
	 function coder it has no generic eval buttons and dedents its source."
	| path mc entry |
	path := application evaluateAndWait: 'GtBridge.Resolve.source_file(', targetModule, ')'.
	(path isString and: [ path asFileReference exists ]) ifFalse: [ ^ self buildHeader ].
	mc := ElixirModuleCoder new
		moduleName: targetModule;
		application: application;
		sourcePath: path.
	entry := mc functionEntries
		detect: [ :e | (e attributeAt: #name) asString = functionName asString
			and: [ (e attributeAt: #arity) = arity ] ]
		ifNone: [ ^ self buildHeader ].
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

{ #category : 'accessing' }
ElixirFunctionExpanderAttribute >> targetModule: mod functionName: fn arity: ar application: app [
	"I record my target's identity; the function coder I build owns its
	 own recompile refresh, so I no longer subscribe to module events."
	targetModule := mod.
	functionName := fn.
	arity := ar.
	application := app
]
