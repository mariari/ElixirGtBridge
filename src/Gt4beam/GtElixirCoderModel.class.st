Class {
	#name : 'GtElixirCoderModel',
	#superclass : 'GtSourceCoder',
	#instVars : [
		'application',
		'elixirLinkApplicationStrategy'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'instance creation' }
GtElixirCoderModel class >> code: aString [

	^ self new sourceCode:
		  (GtCoderExplicitStringSource new source: aString)
]

{ #category : 'converting' }
GtElixirCoderModel >> asCoderViewModel [
	^ GtElixirSnippetCoderViewModel new coder: self
]

{ #category : 'accessing' }
GtElixirCoderModel >> bindAndExecute: sourceString inContext: aContext sessionId: sid [
	| fullSource selfObj |
	selfObj := [ aContext requesterObject selfObject ]
		on: Error do: [ nil ].
	fullSource := ((selfObj isKindOf: BeamProxyObject)
		or: [ selfObj isKindOf: BeamAtomObject ])
		ifTrue: [ 'self = ' , selfObj resolve , String cr , sourceString ]
		ifFalse: [ sourceString ].
	^ self bindAndExecuteRaw: fullSource sessionId: sid
]

{ #category : 'accessing' }
GtElixirCoderModel >> bindAndExecuteRaw: sourceString sessionId: sid [
	| factory |
	self initializeApplication.
	factory := application newCommandFactory.
	sid ifNotNil: [ factory sessionId: sid ].
	^ factory
		<< sourceString;
		sendAndWait
]

{ #category : 'accessing' }
GtElixirCoderModel >> computeAst: theSourceString [
	^ ElixirParser
		parseWithErrors: theSourceString
]

{ #category : 'private' }
GtElixirCoderModel >> doFetchBindingsWithSessionId: sid [
	| serverAddress url response raw result payload |
	application ifNil: [ ^ Dictionary new ].
	serverAddress := application settings serverSocketAddress.
	serverAddress ifNil: [ ^ Dictionary new ].
	url := 'http://' , serverAddress ipOrName , ':'
		, serverAddress port asString , '/BINDINGS'.
	payload := Dictionary new.
	sid ifNotNil: [ payload at: #sessionId put: sid ].
	response := ZnClient new
		url: url;
		entity: (ZnEntity
				with: (STONJSON toString: payload)
				type: ZnMimeType applicationJson);
		post;
		response.
	response isSuccess ifFalse: [ ^ Dictionary new ].
	raw := STONJSON fromString: response contents.
	result := Dictionary new: raw size.
	raw keysAndValuesDo: [ :name :value |
		result at: name put: (self reifyBindingValue: value) ].
	^ result
]

{ #category : 'accessing' }
GtElixirCoderModel >> elixirLinkApplicationStrategy: anApplicationStrategy [
	elixirLinkApplicationStrategy := anApplicationStrategy
]

{ #category : 'private' }
GtElixirCoderModel >> ensureSessionFinalizerFor: viewBindings sessionId: sid coderViewModel: aCoderVM [
	aCoderVM ifNil: [ ^ self ].
	aCoderVM sessionFinalizerRegistered ifTrue: [ ^ self ].
	viewBindings ifNil: [ ^ self ].
	sid ifNil: [ ^ self ].
	FinalizationRegistry default
		add: viewBindings
		finalizer: (BeamSessionFinalizer
			sessionId: sid
			application: application).
	aCoderVM sessionFinalizerRegistered: true
]

{ #category : 'private' }
GtElixirCoderModel >> fetchBindingsWithSessionId: sid [
	^ [ self doFetchBindingsWithSessionId: sid ] on: Error do: [ Dictionary new ]
]

{ #category : 'accessing' }
GtElixirCoderModel >> initializeAddOns: addOns [
	super initializeAddOns: addOns.

	addOns
		addStyler: (GtCoderAstSmaCCParserStyler new smaccStyler: ElixirParser gtStyler).

	elixirLinkApplicationStrategy
		ifNotNil: [ addOns
				addMainAction: 'Inspect' translated
				icon: BrGlamorousVectorIcons playinspect
				action: [ :aCoderUIModel :anElement |
					GtCoderCodeExecutor doItAndGo
						coderViewModel: aCoderUIModel;
						element: anElement;
						execute ]
				id: GtSourceCoderDoItAndGoActionId.
			addOns
				addMainAction: 'Evaluate' translated
				icon: BrGlamorousVectorIcons play
				action: [ :aCoderUIModel :anElement |
					GtCoderCodeExecutor doIt
						coderViewModel: aCoderUIModel;
						element: anElement;
						execute ]
				id: GtSourceCoderDoItActionId ]
]

{ #category : 'accessing' }
GtElixirCoderModel >> initializeApplication [
	application := elixirLinkApplicationStrategy applicationServer.
	application isRunning ifFalse: [ application start ].
	^ application
]

{ #category : 'accessing' }
GtElixirCoderModel >> initializeShortcuts: addOns [
	super initializeShortcuts: addOns.

	elixirLinkApplicationStrategy
		ifNotNil: [ addOns
				addShortcut: GtSourceCoderDoItShortcut new;
				addShortcut: GtSourceCoderDoItAndInspectShortcut new ]
]

{ #category : 'accessing' }
GtElixirCoderModel >> newCompletionStrategy [
	^ GtCompletionStrategy new
]

{ #category : 'accessing' }
GtElixirCoderModel >> primitiveEvaluate: aSourceString inContext: aContext onFailDo: anEvaluationFailBlock [
	| coderVM viewBindings sid result bindings |
	coderVM := [ aContext requesterObject coderViewModel ]
		on: Error do: [ nil ].
	viewBindings := coderVM ifNotNil: [ coderVM viewPharoBindings ].
	sid := viewBindings
		ifNotNil: [ LeElixirSnippetElement sessionIdFor: viewBindings ].
	result := self bindAndExecute: aSourceString
		inContext: aContext
		sessionId: sid.
	self ensureSessionFinalizerFor: viewBindings
		sessionId: sid
		coderViewModel: coderVM.
	bindings := self fetchBindingsWithSessionId: sid.
	bindings associationsDo: [ :assoc |
		viewBindings ifNotNil: [
			(viewBindings bindingOf: assoc key asSymbol) value: assoc value ] ].
	^ result
]

{ #category : 'private' }
GtElixirCoderModel >> reifyBindingValue: aValue [
	"Proxy references carry exid+exclass; reify as BeamProxyObject.
	Everything else passes through as a primitive."
	(aValue isDictionary and: [ aValue includesKey: 'exid' ])
		ifTrue: [
			^ (BeamProxyObject elixirClass: (aValue at: 'exclass'))
				elixirVar: (aValue at: 'exid');
				application: application ].
	^ aValue
]

{ #category : 'accessing' }
GtElixirCoderModel >> sourceFrom: trimmedSourceString returnedVarNames: varNames [
	"Answer the modified source to return the declared variables"
	^ String
		streamContents: [ :stream |
			stream << trimmedSourceString ]
]
