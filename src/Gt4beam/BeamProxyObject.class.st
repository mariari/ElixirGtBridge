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

{ #category : 'as yet unclassified' }
BeamProxyObject >> asList [
	^ (1 to: self length) collect: [ :anIndex | self itemAt: anIndex - 1 ]
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> attributeAt: name [
	^ self
		evaluateAndWait: 'GtBridge.ObjectRegistry.get_attribute(' , self elixirVar asString , ',', name resolve, ')'
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
	"Create a composite view with all remote views"

	<gtView>
	| viewDecls |
	viewDecls := self viewDeclarations asList.

	viewDecls ifEmpty: [ ^ aView empty ].

	^ aView composite
		title: 'Remote views';
		priority: 1;
		views: (viewDecls collect: [ :decl | self viewFromDeclaration: decl ])
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> gtSourceFor: aView [
	<gtView>
	^ aView textEditor
		title: 'Source';
		priority: 110;
		text: [ self source ];
		aptitude: BrGlamorousCodeEditorAptitude;
		styler: ElixirParser gtStyler
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
BeamProxyObject >> source [
	| file |
	file := self sourceFile asFileReference.

	file exists ifTrue: [ ^ file contents ].

	^ nil
]

{ #category : 'as yet unclassified' }
BeamProxyObject >> sourceFile [
	^ self
		evaluateAndWait: 'List.to_string(' , self resolve , '.__struct__.module_info(:compile)[:source])'
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
