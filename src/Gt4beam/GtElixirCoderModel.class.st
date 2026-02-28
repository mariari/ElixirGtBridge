Class {
	#name : 'GtElixirCoderModel',
	#superclass : 'GtSourceCoder',
	#instVars : [
		'pharoBindings',
		'exception',
		'application',
		'commandFactory',
		'elixirLinkApplicationStrategy',
		'sessionId',
		'sessionFinalizerRegistered'
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
GtElixirCoderModel >> bindAndExecute: sourceString inContext: aContext [
	| fullSource selfObj |

	<gtIgnoreConstraint: #GtRBAcceptVisitorCalledFromNonVisitingMethods>
	<remoteDebuggerSignal>
	selfObj := [ aContext requesterObject selfObject ]
		on: Error do: [ nil ].
	fullSource := ((selfObj isKindOf: BeamProxyObject)
		or: [ selfObj isKindOf: BeamAtomObject ])
		ifTrue: [ 'self = ' , selfObj resolve , String cr , sourceString ]
		ifFalse: [ sourceString ].
	^ self bindAndExecuteRaw: fullSource
]

{ #category : 'accessing' }
GtElixirCoderModel >> bindAndExecuteRaw: sourceString [
	self initializeApplication.
	self ensureSessionFinalizer.
	commandFactory := application newCommandFactory.
	commandFactory sessionId: sessionId.

	^ commandFactory
		<< sourceString;
		sendAndWait
]

{ #category : 'private' }
GtElixirCoderModel >> ensureSessionFinalizer [
	"I register a BeamSessionFinalizer on the per-view bindings object.
	When bindings is GC'd (view closed), the finalizer fires SESSION_CLOSE.
	Uses FinalizationRegistry directly — the execution handler's
	weakRegistry ivar has no public accessor."
	sessionFinalizerRegistered == true ifTrue: [ ^ self ].
	pharoBindings ifNil: [ ^ self ].
	sessionId ifNil: [ ^ self ].
	FinalizationRegistry default
		add: pharoBindings
		finalizer: (BeamSessionFinalizer
			sessionId: sessionId
			application: application).
	sessionFinalizerRegistered := true
]

{ #category : 'accessing' }
GtElixirCoderModel >> computeAst: theSourceString [
	^ ElixirParser
		parseWithErrors: theSourceString
]

{ #category : 'private' }
GtElixirCoderModel >> doFetchBindings [
	| serverAddress url response raw result payload |
	application ifNil: [ ^ Dictionary new ].
	serverAddress := application settings serverSocketAddress.
	serverAddress ifNil: [ ^ Dictionary new ].
	url := 'http://' , serverAddress ipOrName , ':'
		, serverAddress port asString , '/BINDINGS'.
	payload := Dictionary new.
	sessionId ifNotNil: [ payload at: #sessionId put: sessionId ].
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
GtElixirCoderModel >> sessionId [
	^ sessionId
]

{ #category : 'accessing' }
GtElixirCoderModel >> sessionId: aString [
	sessionId := aString
]

{ #category : 'accessing' }
GtElixirCoderModel >> elixirLinkApplicationStrategy: anApplicationStrategy [
	elixirLinkApplicationStrategy := anApplicationStrategy
]

{ #category : 'accessing' }
GtElixirCoderModel >> exception [
	^ exception
]

{ #category : 'private' }
GtElixirCoderModel >> fetchBindings [
	^ [ self doFetchBindings ] on: Error do: [ Dictionary new ]
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
GtElixirCoderModel >> pharoBindings: anObject [
	pharoBindings := anObject
]

{ #category : 'accessing' }
GtElixirCoderModel >> primitiveEvaluate: aSourceString inContext: aGtSourceCoderEvaluationContext onFailDo: anEvaluationFailBlock [
	| result bindings |
	self resolvePerViewState: aGtSourceCoderEvaluationContext.
	result := self bindAndExecute: aSourceString inContext: aGtSourceCoderEvaluationContext.
	bindings := self fetchBindings.
	bindings associationsDo: [ :assoc |
		pharoBindings ifNotNil: [
			(pharoBindings bindingOf: assoc key asSymbol) value: assoc value ] ].
	"Release so the coder model (persisted via snippet) does not pin
	the per-view bindings.  The finalizer is already registered and
	resolvePerViewState: will re-set pharoBindings on next eval."
	pharoBindings := nil.
	^ result
]

{ #category : 'private' }
GtElixirCoderModel >> resolvePerViewState: aContext [
	"The coder model is shared between views (same snippet model).
	Resolve the per-view pharoBindings and sessionId from the
	evaluation context so each view gets its own Elixir session."
	| coderVM viewBindings newSessionId |
	coderVM := [ aContext requesterObject coderViewModel ]
		on: Error do: [ nil ].
	coderVM ifNil: [ ^ self ].
	viewBindings := coderVM viewPharoBindings.
	viewBindings ifNil: [ ^ self ].
	pharoBindings := viewBindings.
	newSessionId := LeElixirSnippetElement sessionIdFor: viewBindings.
	newSessionId = sessionId ifFalse: [
		sessionFinalizerRegistered := nil ].
	sessionId := newSessionId
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

{ #category : 'accessing' }
GtElixirCoderModel >> variableBindings: aGtSnippetBindings [

	^ self pharoBindings: aGtSnippetBindings
]
