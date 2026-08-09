Class {
	#name : 'BeamProxyObject',
	#superclass : 'Object',
	#instVars : [
		'elixirClass',
		'elixirVar',
		'rawData',
		'value',
		'application'
	],
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'as yet unclassified' }
BeamProxyObject class >> elixirClass [
	^ self subclassResponsibility
]

{ #category : 'as yet unclassified' }
BeamProxyObject class >> elixirClass: aClass [
	| proxyClass proxyClasses |
	proxyClasses := (self allSubclasses
			collect: [ :each | each elixirClass -> each ]) asDictionary.
	proxyClass := proxyClasses at: aClass ifAbsent: [ BeamProxyObject ].
	^ proxyClass new elixirClass: aClass
]

{ #category : 'wire' }
BeamProxyObject class >> fetch: anElixirSource through: anApplication [
	"I answer what anElixirSource evaluates to as bridge data in one
	 round trip, or the BeamBridgeEvalError the node replied with. I
	 bracket the source: Elixir binds |> into a bare macro call's last
	 argument."
	| json |
	json := anApplication newCommandFactory
		<< ('(' , anElixirSource , ') |> GtBridge.Serializer.to_json() |> elem(1)');
		sendAndWait.
	json isString ifFalse: [ ^ json ].
	^ (BeamLinkDeserializer onApplication: anApplication) decodeJson: json
]

{ #category : 'as yet unclassified' }
BeamProxyObject class >> leProxyTypeForPlaygroundPage [
	^ BeamProxyObject
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> = AnotherObject [
	^ super = AnotherObject
		ifFalse: [ self class = AnotherObject class
				and: [ self asString = AnotherObject asString ] ]
		ifTrue: [ true ]
]

{ #category : 'accessing' }
BeamProxyObject >> application [
	^ application
]

{ #category : 'accessing' }
BeamProxyObject >> application: anObject [
	application := anObject
]

{ #category : 'accessing' }
BeamProxyObject >> applicationAnalysis [
	"I return the ElixirApplicationAnalysis for the application that
	 defines my Elixir class, or nil if my class isn't loaded or
	 doesn't belong to any tracked application. Subclasses that wrap
	 something other than their elixirClass (e.g. BeamDocumentationObject
	 wraps a Documentation struct whose documented module differs from
	 GtBridge.Documentation) override this."

	| appAtom sys |
	elixirClass ifNil: [ ^ nil ].
	appAtom := self
			evaluateAndWait:
				'GtBridge.Analysis.LoadedModules.app_of(' , elixirClass , ')'.
	appAtom ifNil: [ ^ nil ].
	sys := ElixirSystemAnalysis onApplication: self application.
	^ sys applications
		detect: [ :each | each name symbol = appAtom symbol ]
		ifNone: [ nil ]
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> asList [
	"I materialise my whole list in one bridge call.

	 The previous form sent `length` and then one `Enum.at(i)` per
	 element: N+1 round trips, and O(n^2) traversal on the BEAM because
	 Enum.at/2 walks a linked list.  Listing a 52-function module cost
	 53 requests and 71ms; it now costs one request and 9ms.

	 Elements arrive as values, wrapped in BeamValue so they answer the
	 same reading protocol I do, except pids, which the decoder rebuilds
	 as live BeamPIDObjects from their printed form.

	 I fall back to the per-element path when the node could not answer
	 or the reply would not decode."
	| decoded |
	decoded := [ self fetch: self resolve ] on: Error do: [ nil ].
	decoded isArray ifFalse: [ ^ self asListElementByElement ].
	^ decoded collect: [ :each | BeamValue wrapping: each ]
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> asListElementByElement [
	"The original one-round-trip-per-element materialisation, kept as
	 the fallback for contents the serializer cannot represent."
	^ (1 to: self length) collect: [ :anIndex | self itemAt: anIndex - 1 ]
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> attributeAt: name [
	| resolvedName |
	resolvedName := name isSymbol
		ifTrue: [ self elixirAtomFor: name asString ]
		ifFalse: [ name isString
			ifTrue: [ '"', name, '"' ]
			ifFalse: [ (name respondsTo: #resolve)
				ifTrue: [ name resolve ]
				ifFalse: [ (name isKindOf: ByteArray)
					ifTrue: [ '<<', (', ' join: (name asArray collect: #asString)), '>>' ]
					ifFalse: [ name asString ] ] ] ].
	^ self
		evaluateAndWait: 'GtBridge.ObjectRegistry.get_attribute(' , self elixirVar asString , ',', resolvedName, ')'
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> attributes [
	^ self
		evaluateAndWait: 'GtBridge.ObjectRegistry.list_attributes(' , self elixirVar asString , ')'
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> attributesAndValues [
	^ self attributes asList
		collect: [ :anItem | anItem -> (self attributeAt: anItem) ]
]

{ #category : 'private' }
BeamProxyObject >> elixirAtomFor: aString [
	"I return an Elixir atom literal, quoted if the name contains non-identifier characters."
	(aString allSatisfy: [ :c | c isAlphaNumeric or: [ c = $_ ] ])
		ifTrue: [ ^ ':', aString ].
	^ ':"', aString, '"'
]

{ #category : 'accessing' }
BeamProxyObject >> elixirClass [
	^ elixirClass
]

{ #category : 'accessing' }
BeamProxyObject >> elixirClass: anObject [
	elixirClass := anObject
]

{ #category : 'accessing' }
BeamProxyObject >> elixirVar [
	^ elixirVar
]

{ #category : 'accessing' }
BeamProxyObject >> elixirVar: anObject [
	elixirVar := anObject
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> evaluateAndWait: string [
	^ self application newCommandFactory
		<< string;
		sendAndWait
]

{ #category : 'wire' }
BeamProxyObject >> fetch: anElixirSource [
	"I evaluate against my node; `self fetch: self resolve` reads me back."
	^ self class fetch: anElixirSource through: self application
]

{ #category : 'accessing' }
BeamProxyObject >> functionLines [
	^ nil
]

{ #category : 'gt-actions' }
BeamProxyObject >> gtActionApplicationFor: anAction [
	<gtAction>
	"I add a toolbar button that spawns the ElixirApplicationAnalysis
	 for the application that defines my class. Silently no-ops when
	 the class doesn't belong to a tracked application."
	^ anAction button
		icon: BrGlamorousVectorIcons hierarchy;
		label: 'Application';
		action: [ :aButton |
			self applicationAnalysis ifNotNil: [ :app |
				aButton phlow spawnObject: app ] ]
]

{ #category : 'gt-views' }
BeamProxyObject >> gtBeamPrintFor: aView [
	<gtView>
	<gtBeamView>
	"I show the Elixir inspect() output for this object in
	 monospace, matching GT's standard Print view style."
	^ aView textEditor
		title: 'Print';
		priority: 115;
		aptitude: BrGlamorousCodeEditorAptitude;
		text: [ self evaluateAndWait: self resolve , ' |> inspect(pretty: true)' ];
		actionUpdateButton
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> gtCoderFor: aView [
	<gtView>
	<gtBeamView>
	"I show the Elixir module for this object in a module coder.
	 The object is passed as selfObject so single-arity functions
	 can Run with this value piped as their first argument."
	| modName |
	elixirClass isNil ifTrue: [ ^ aView empty ].
	modName := 'Elixir.', elixirClass.
	^ aView explicit
		title: 'Meta';
		priority: 199;
		stencil: [
			| coder |
			coder := ElixirModuleCoder
				forModule: modName
				application: application.
			coder selfObject: self.
			coder asCoderViewModel asElement ]
]

{ #category : 'gt-extensions' }
BeamProxyObject >> gtDefaultInspectorTool [
	"I collect inspector modes via <gtInspectorMode> pragmas.
	 Self mode is always included. R/P toggle shows even with
	 a single mode for consistent Proxy access."
	| modes |
	modes := BeamInspectorModeCollector new
		fromObject: self;
		collect.
	^ BeamProxyToggleCompositeTool fromModes: modes
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> gtElixirRawFor: aView [
	<gtView>
	<gtBeamView>
	| attrs |
	attrs := [ self attributesAndValues ] on: Error do: [ #() ].
	attrs isEmpty ifTrue: [ ^ aView empty ].
	^ aView columnedTree
		title: 'Raw';
		priority: 99;
		items: [ attrs ];
		children: [ :anItem |
			(anItem value isKindOf: BeamProxyObject)
				ifTrue: [ anItem value attributesAndValues ]
				ifFalse: [ {} ] ];
		column: 'Variable' text: #key;
		column: 'Value' text: #value;
		send: #value;
		actionUpdateButton
]

{ #category : 'gt-extensions' }
BeamProxyObject >> gtInspectorVariableNodesIn: aCollection [
	"I read as Elixir: my variables are the attributes of the object I
	 proxy, not the Pharo slots holding the connection to it. An atom
	 key answers #symbol, and I label it by its name so a field reads
	 as scheme rather than as Smalltalk's #scheme."
	| attrs |
	attrs := [ self attributesAndValues ] on: Error do: [ #() ].
	attrs do: [ :each |
		aCollection add: (GtInspectorDynamicNode
			hostObject: self
			label: ((each key respondsTo: #symbol)
				ifTrue: [ each key symbol asString ]
				ifFalse: [ each key asString ])
			value: each value) ]
]

{ #category : 'gt-extensions' }
BeamProxyObject >> gtProxyInspectorContentFor: aView [
	"I build the Proxy tab's labelled content — GT wrapper views
	 only, no BEAM data views."
	^ GtPhlowLabelledViewBuilder new
		object: self;
		view: aView;
		context: GtPhlowContext new;
		viewsSelector: #gtViewsForProxySideInContext:;
		titleComputation: [ self class name ];
		build
]

{ #category : 'gt-extensions' }
BeamProxyObject >> gtProxySideInspectorTool [
	"I return an inspector tool showing only GT wrapper views
	 (no BEAM data views) — for the Proxy tab."
	^ GtInspectorTool
		forObject: self
		viewSelector: #gtProxyInspectorContentFor:
]

{ #category : 'gt-extensions' }
BeamProxyObject >> gtRemoteInspectorContentFor: aView [
	<return: #GtPhlowLabelledView>
	"I build the Remote tab's labelled content by collecting views via
	 #gtViewsForRemoteSideInContext: and wrapping them with a title."
	^ GtPhlowLabelledViewBuilder new
		object: self;
		view: aView;
		context: GtPhlowContext new;
		viewsSelector: #gtViewsForRemoteSideInContext:;
		titleComputation: [
			elixirClass
				ifNil: [ '<anonymous>' ]
				ifNotNil: [ :cls |
					String streamContents: [ :stream |
						stream
							<< (cls first isVowel ifTrue: [ 'an ' ] ifFalse: [ 'a ' ]);
							<< cls ] ] ];
		build
]

{ #category : 'gt-extensions' }
BeamProxyObject >> gtRemoteSideInitialPlaygroundSnippet [
	^ LeElixirSnippet new
]

{ #category : 'gt-extensions' }
BeamProxyObject >> gtRemoteSideInspectorTool [
	"I return the inspector tool for the Remote tab — a GtInspectorTool
	 that routes view collection through gtRemoteInspectorContentFor:."
	^ GtInspectorTool
		forObject: self
		viewSelector: #gtRemoteInspectorContentFor:
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> gtRemoteViewsFor: aView [
	"I show all server-side declared views as a single composite.
	 Tagged <gtProxyView> so I only appear under the Proxy mode — the
	 Remote mode already shows each remote view as its own top-level
	 tab via gtViewsForRemoteSideInContext:."
	<gtView>
	<gtProxyView>
	| viewDecls |
	viewDecls := self viewDeclarations asList.

	viewDecls ifEmpty: [ ^ aView empty ].

	viewDecls size = 1
		ifTrue: [ ^ self viewFromDeclaration: viewDecls first ].

	^ aView composite
		title: 'Remote views';
		priority: 1;
		views: (viewDecls collect: [ :decl | self viewFromDeclaration: decl ])
]

{ #category : 'gt-extensions' }
BeamProxyObject >> gtSpotterActDefaultFrom: aSpotterElement [
	"I open my composite inspector tool in a pager instead of
	 the default plain GtInspector, preserving the R|P toggle."
	| tool |
	tool := self gtDefaultInspectorTool.
	BlSpace new
		inPager: tool;
		title: tool name;
		icon: tool icon;
		withSceneDriller;
		showFrom: aSpotterElement
]

{ #category : 'gt-extensions' }
BeamProxyObject >> gtViewsForProxySideInContext: aContext [
	"I collect views for the Proxy tab: all local views EXCEPT
	 those tagged <gtBeamView>. This shows the GT wrapper views
	 (Raw, Print, Meta) and any <gtProxyView> views, but hides
	 BEAM data views which belong in Remote mode."
	^ (super gtViewsInContext: aContext) reject: [ :each |
		each definingMethod compiledMethod hasPragmaNamed: #gtBeamView ]
]

{ #category : 'gt-extensions' }
BeamProxyObject >> gtViewsForRemoteSideInContext: aContext [
	"I collect views for the Remote tab: local views tagged
	 <gtBeamView> (BEAM data views only, no generic GT views
	 like Raw/Print/Meta), plus any server-side view declarations
	 registered via GtBridge.GtViewedObject on the remote object."
	| localBeamViews collectedViews |
	localBeamViews := (super gtViewsInContext: aContext) select: [ :each |
		each definingMethod compiledMethod hasPragmaNamed: #gtBeamView ].
	collectedViews := OrderedCollection new
		addAll: localBeamViews;
		addAll: (self remoteViewsInContext: aContext);
		yourself.
	GtPhlowUtility sortByPriority: collectedViews.
	^ collectedViews
]

{ #category : 'comparing' }
BeamProxyObject >> hash [
	^ self class hash hashMultiply bitXor: self asString hash hashMultiply
]

{ #category : 'gt-extensions' }
BeamProxyObject >> inspectorModeName [
	"I return my display name for the inspector mode tab.
	 Subclasses override for type-specific names."
	^ 'Remote'
]

{ #category : 'predicates' }
BeamProxyObject >> isError [
	^ false
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> itemAt: idx [
	^ self evaluateAndWait: self resolve , '|> Enum.at(' , idx asString , ')'
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> length [
	^ self evaluateAndWait: self resolve , '|> length()'
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> printOn: str [
	str << (self evaluateAndWait: self resolve , '|> inspect(pretty: true)')
]

{ #category : 'accessing' }
BeamProxyObject >> rawData [
	^ rawData
]

{ #category : 'accessing' }
BeamProxyObject >> rawData: anObject [
	rawData := anObject
]

{ #category : 'accessing' }
BeamProxyObject >> remoteClass [
	"I return my Elixir class — used by GT's proxy-side playground
	 strategy and inspector page keys."
	^ elixirClass
]

{ #category : 'gt-extensions' }
BeamProxyObject >> remoteViewsInContext: aContext [
	"I return the server-side declarative views for this proxy — one
	 GtPhlowView per view declaration registered on the remote object.
	 Empty if the bridge can't reach the server or the object has no
	 declared views."
	^ [ self viewDeclarations asList
		collect: [ :decl | self viewFromDeclaration: decl ] ]
		on: Error do: [ #() ]
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> resolve [
	^ 'GtBridge.ObjectRegistry.resolve(' , self elixirVar asString , ')'
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> sourceFile [
	^ self
		evaluateAndWait: 'GtBridge.Resolve.source_file(' , self resolve , ')'
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> viewDeclarations [
	^ self
		evaluateAndWait: 'GtBridge.GtViewedObject.get_views_declarations_by_id(' , self elixirVar asString
				, ')'
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> viewFromDeclaration: aDeclaration [
	^ (GtBeamViewDeclaration fromRawData: aDeclaration) asView
]
