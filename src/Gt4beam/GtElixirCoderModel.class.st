Class {
	#name : 'GtElixirCoderModel',
	#superclass : 'GtSourceCoder',
	#instVars : [
		'pharoBindings',
		'exception',
		'application',
		'commandFactory',
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

{ #category : 'private' }
GtElixirCoderModel >> atomKeyed: aDictionary at: aName [
	"Read `aName` whether it arrived plain or `__atom__:`-prefixed."
	^ aDictionary
		at: aName
		ifAbsent: [ aDictionary at: '__atom__:' , aName ifAbsent: [ nil ] ]
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
	commandFactory := application newCommandFactory.

	^ commandFactory
		<< sourceString;
		sendAndWait
]

{ #category : 'accessing' }
GtElixirCoderModel >> computeAst: theSourceString [
	^ ElixirParser
		parseWithErrors: theSourceString
]

{ #category : 'private' }
GtElixirCoderModel >> doFetchBindings [
	| serverAddress url response raw result |
	application ifNil: [ ^ Dictionary new ].
	serverAddress := application settings serverSocketAddress.
	serverAddress ifNil: [ ^ Dictionary new ].
	url := 'http://' , serverAddress ipOrName , ':'
		, serverAddress port asString , '/BINDINGS'.
	response := ZnClient new
		url: url;
		entity: (ZnEntity
				with: '{}'
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
	result := self bindAndExecute: aSourceString inContext: aGtSourceCoderEvaluationContext.
	bindings := self fetchBindings.
	bindings associationsDo: [ :assoc |
		pharoBindings ifNotNil: [
			(pharoBindings bindingOf: assoc key asSymbol) value: assoc value ] ].
	^ result
]

{ #category : 'private' }
GtElixirCoderModel >> reifyBindingValue: aValue [
	"Proxy references carry exid+exclass; reify as BeamProxyObject.
	Everything else passes through as a primitive.

	The reference arrives keyed either plainly or with an `__atom__:`
	prefix, depending on which encoder ran on the BEAM: `Jason.encode`
	emits `exid`, `GtBridge.Serializer.to_json` marks atom-valued map
	keys and emits `__atom__:exid`."
	(aValue isDictionary and: [ (self atomKeyed: aValue at: 'exid') notNil ])
		ifTrue: [
			^ (BeamProxyObject elixirClass: (self atomKeyed: aValue at: 'exclass'))
				elixirVar: (self atomKeyed: aValue at: 'exid');
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
