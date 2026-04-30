Class {
	#name : 'GtElixirCoderModel',
	#superclass : 'GtSourceCoder',
	#traits : 'TElixirNavigationCoder',
	#classTraits : 'TElixirNavigationCoder classTrait',
	#instVars : [
		'application',
		'elixirLinkApplicationStrategy',
		'preambleLines',
		'contextModuleName'
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

{ #category : 'accessing' }
GtElixirCoderModel >> application [

	"I return the BEAM application, initializing it if needed."

	application ifNil: [ self initializeApplication ].
	^ application
]

{ #category : 'converting' }
GtElixirCoderModel >> asCoderViewModel [
	^ GtElixirSnippetCoderViewModel new coder: self
]

{ #category : 'accessing' }
GtElixirCoderModel >> bindAndExecute: sourceString inContext: aContext sessionId: sid [
	"I prepend preamble, import, and self binding, then eval."
	| selfObj |
	selfObj := self selfObjectFor: aContext.
	self initializeApplication.
	self ensurePreambleLoaded: selfObj.
	^ self
		bindAndExecuteRaw: (self wrapSource: sourceString withSelf: selfObj)
		sessionId: sid
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

{ #category : 'accessing' }
GtElixirCoderModel >> contextModuleName [
	^ contextModuleName
]

{ #category : 'accessing' }
GtElixirCoderModel >> contextModuleName: aString [
	contextModuleName := aString
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
GtElixirCoderModel >> ensurePreambleLoaded: selfObj [
	"I fetch and cache the module's preamble directives (aliases,
	 requires) from the bridge. Called once, cached for the life
	 of this coder instance."
	| modName result |
	preambleLines ifNotNil: [ ^ self ].
	modName := (selfObj respondsTo: #elixirClass)
		ifTrue: [ selfObj elixirClass ]
		ifFalse: [ nil ].
	modName ifNil: [ preambleLines := #(). ^ self ].
	result := application evaluateAndWait:
		'GtBridge.Eval.Preamble.directives(' , modName , ') |> Enum.join("\n")'.
	preambleLines := result isEmpty
		ifTrue: [ #() ]
		ifFalse: [ result lines ]
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
	addOns
		addStyler: ElixirFunctionExpanderStyler new.

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
	"Register unconditionally — Lepiter snippets set the strategy
	 after addOns init, so an `ifNotNil:` guard would skip them."
	super initializeShortcuts: addOns.
	addOns
		addShortcut: GtSourceCoderDoItShortcut new;
		addShortcut: GtSourceCoderDoItAndInspectShortcut new;
		addShortcut: GtSourceCoderSaveShortcut new;
		addShortcut: ElixirCoderFormatShortcut new.
	self initializeNavigationShortcuts: addOns
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
	Base64-tagged arrays carry non-UTF-8 binaries; decode as ByteArray.
	Recurses into collections to handle nested values."
	(aValue isDictionary and: [ aValue includesKey: 'exid' ])
		ifTrue: [
			^ (BeamProxyObject elixirClass: (aValue at: 'exclass'))
				elixirVar: (aValue at: 'exid');
				application: application ].
	(aValue isArray and: [ aValue size = 2 and: [ aValue first = '__base64__' ] ])
		ifTrue: [ ^ (ZnBase64Encoder new decode: aValue second) asByteArray ].
	aValue isDictionary
		ifTrue: [
			| result |
			result := Dictionary new: aValue size.
			aValue keysAndValuesDo: [ :k :v |
				result at: k put: (self reifyBindingValue: v) ].
			^ result ].
	aValue isArray
		ifTrue: [ ^ aValue collect: [ :elem | self reifyBindingValue: elem ] ].
	^ aValue
]

{ #category : 'private' }
GtElixirCoderModel >> selfObjectFor: aContext [
	"I return the inspector selfObject from aContext's requester, or nil
	 if the snippet isn't in an inspector playground."
	| req |
	req := aContext requesterObject.
	^ (req notNil and: [ req respondsTo: #selfObject ])
		ifTrue: [ req selfObject ]
		ifFalse: [ nil ]
]

{ #category : 'private' }
GtElixirCoderModel >> wrapSource: sourceString withSelf: selfObj [
	"I prepend preamble (aliases, requires), import, and self binding
	 so snippets have the module's full environment from the first eval."
	(selfObj notNil and: [ selfObj respondsTo: #resolve ])
		ifFalse: [ ^ sourceString ].
	^ String streamContents: [ :s |
		(preambleLines ifNil: [ #() ]) do: [ :line |
			s nextPutAll: line; nextPut: Character lf ].
		(selfObj respondsTo: #elixirClass) ifTrue: [
			selfObj elixirClass ifNotNil: [ :modName |
				s nextPutAll: 'import '; nextPutAll: modName; nextPut: Character lf ] ].
		s
			nextPutAll: 'self = '; nextPutAll: selfObj resolve; nextPut: Character lf;
			nextPutAll: sourceString ]
]
