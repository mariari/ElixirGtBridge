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
	appAtom := self evaluateAndWait:
		'Application.get_application(', elixirClass, ')'.
	appAtom ifNil: [ ^ nil ].
	sys := ElixirSystemAnalysis onApplication: self application.
	^ sys applications
		detect: [ :each | each name symbol = appAtom symbol ]
		ifNone: [ nil ]
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> asList [
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

{ #category : 'private' }
BeamProxyObject >> elixirAtomFor: aString [
	"I return an Elixir atom literal, quoted if the name contains non-identifier characters."
	(aString allSatisfy: [ :c | c isAlphaNumeric or: [ c = $_ ] ])
		ifTrue: [ ^ ':', aString ].
	^ ':"', aString, '"'
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

{ #category : 'gt-extensions' }
BeamProxyObject >> filterLocalProxyViews: localViews [
	"I remove views tagged <gtProxyView> from the Remote tab list so
	 they appear only under Proxy mode."
	^ localViews reject: [ :each |
		each definingMethod compiledMethod hasPragmaNamed: #gtProxyView ]
]

{ #category : 'gt-extensions' }
BeamProxyObject >> gtDefaultInspectorTool [
	"I return a composite tool with a Remote / Proxy toggle at the top,
	 mirroring GT's Python bridge (PBProxyObject >> gtDefaultInspectorTool).

	 - Remote shows Elixir-side views: Coder, Source, the playground
	   snippet, raw attribute tree, and any remote view declarations
	   registered via GtBridge.GtViewedObject.
	 - Proxy shows the Smalltalk BeamProxyObject wrapper itself — its
	   ivars (elixirClass, elixirVar, rawData, application) plus any
	   local <gtView> also tagged <gtProxyView>.

	 Skipping GT's third Runtime tool — the BeamLinkApplication is
	 available directly from the Elixir side inspector and duplicating
	 it here adds no value for single-application bridges."
	^ GtPhlowCompositeTool new
		addTool: (self gtRemoteSideInspectorTool
			name: 'Remote';
			withLabelAndIconAptitude);
		addTool: (super gtDefaultInspectorTool
			name: 'Proxy';
			withLabelAndIconAptitude)
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
BeamProxyObject >> gtRemoteSideInspectorTool [
	"I return the inspector tool for the Remote tab — a GtInspectorTool
	 that routes view collection through gtRemoteInspectorContentFor:."
	^ GtInspectorTool
		forObject: self
		viewSelector: #gtRemoteInspectorContentFor:
]

{ #category : 'gt-extensions' }
BeamProxyObject >> gtViewsForRemoteSideInContext: aContext [
	"I collect views for the Remote tab: all local <gtView> methods that
	 are NOT tagged <gtProxyView>, plus any server-side view declarations
	 registered via GtBridge.GtViewedObject on the remote object."
	| localViews collectedViews |
	localViews := super gtViewsInContext: aContext.
	collectedViews := OrderedCollection new
		addAll: (self filterLocalProxyViews: localViews);
		addAll: (self remoteViewsInContext: aContext);
		yourself.
	GtPhlowUtility sortByPriority: collectedViews.
	^ collectedViews
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

{ #category : 'as yet unclassified' }
BeamProxyObject >> gtCoderFor: aView [
	<gtView>
	"I show the Elixir module for this object in a module coder.
	 The object is passed as selfObject so single-arity functions
	 can Run with this value piped as their first argument."
	| modName |
	elixirClass isNil ifTrue: [ ^ aView empty ].
	modName := 'Elixir.', elixirClass.
	^ aView explicit
		title: 'Coder';
		priority: 30;
		stencil: [
			| coder |
			coder := ElixirModuleCoder
				forModule: modName
				application: application.
			coder selfObject: self.
			coder asCoderViewModel asElement ]
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> gtElixirRawFor: aView [
	<gtView>
	^ aView columnedTree
		title: 'Elixir raw';
		priority: 99;
		items: [ self attributesAndValues ];
		children: [ :anItem | 
			(anItem value isKindOf: BeamProxyObject)
				ifTrue: [ anItem value attributesAndValues ]
				ifFalse: [ {} ] ];
		column: 'Variable' text: #key;
		column: 'Value' text: #value;
		send: #value;
		actionUpdateButton
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

{ #category : 'accessing' }
BeamProxyObject >> functionLines [
	^ nil
]

{ #category : 'gt-views' }
BeamProxyObject >> gtSourceFor: aView [
	<gtView>
	| file |
	file := self sourceFile.
	file isString ifFalse: [ ^ aView empty ].
	file := file asFileReference.
	file exists ifFalse: [ ^ aView empty ].
	^ aView explicit
		title: 'Source';
		priority: 110;
		stencil: [
			| pane lineRange |
			lineRange := [ self functionLines ] on: Error do: [ nil ].
			pane := file gtEditorView.
			pane childNamed: #editor ifFound: [ :editor |
				| aText |
				editor aptitude: BrGlamorousCodeEditorAptitude.
				aText := editor text.
				lineRange ifNotNil: [
					| startChar endChar lines |
					lines := aText asString lines.
					startChar := 0.
					1 to: lineRange first - 1 do: [ :i |
						startChar := startChar + (lines at: i) size + 1 ].
					endChar := startChar.
					lineRange first to: (lineRange second min: lines size) do: [ :i |
						endChar := endChar + (lines at: i) size + 1 ].
					(aText from: startChar + 1 to: endChar)
						attributes: { BlTextDecorationAttribute new underline
							beNotOverwritableByStyler;
							color: BrGlamorousColors textHighlightColor } ].
				editor editor styler: ElixirParser gtStyler.
				lineRange ifNotNil: [
					editor scrollToPosition: lineRange first ] ].
			pane ]
]

{ #category : 'comparing' }
BeamProxyObject >> hash [
	^ self class hash hashMultiply bitXor: self asString hash hashMultiply
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
