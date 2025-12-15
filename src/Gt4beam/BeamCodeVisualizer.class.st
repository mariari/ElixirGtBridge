Class {
	#name : 'BeamCodeVisualizer',
	#superclass : 'Object',
	#category : 'Gt4beam-CodeVisualization',
	#package : 'Gt4beam',
	#tag : 'CodeVisualization'
}

{ #category : 'as yet unclassified' }
BeamCodeVisualizer >> codeView [
	<gtExample>
	^ self packageViewIncluding: self class
]

{ #category : 'as yet unclassified' }
BeamCodeVisualizer >> colorForClass: aClass [
	(aClass methods anySatisfy: [ :m | m isAbstract ]) ifTrue: [ ^ Color blue ].
	aClass superclass = TestCase ifTrue: [ ^ Color orange ].
	(aClass class includesSelector: #confluenceSetup) ifTrue: [ ^ Color cyan ].
	(aClass allSuperclasses includes: BlElement)
		ifTrue: [ ^ Color green muchDarker ].
	(aClass allSuperclasses includes: BrAptitude)
		ifTrue: [ ^ Color yellow muchDarker ].
	^ Color black
]

{ #category : 'as yet unclassified' }
BeamCodeVisualizer >> colorForMethod: aCompiledMethod [
	aCompiledMethod isFromTrait ifTrue: [ ^ Color brown ].
	aCompiledMethod isAbstract ifTrue: [ ^ Color yellow ].
	aCompiledMethod isTestMethod ifTrue: [ ^ Color orange ].
	(aCompiledMethod referencedClasses includes: GtMondrian)
		ifTrue: [ ^ Color cyan ].
	aCompiledMethod isGTExampleMethod ifTrue: [ ^ Color lightOrange ].
	(aCompiledMethod hasPragmaNamed: #gtView)
		ifTrue: [ ^ Color purple muchLighter ].
	(self isAccessor: aCompiledMethod) ifTrue: [ ^ Color blue ].
	^ Color green
]

{ #category : 'as yet unclassified' }
BeamCodeVisualizer >> isAccessor: aCompiledMethod [
	^(self isSimpleGetter: aCompiledMethod) or: [self isSimpleSetter: aCompiledMethod]
]

{ #category : 'as yet unclassified' }
BeamCodeVisualizer >> isSimpleGetter: aMethod [
	"Only a method directly returning an instance variable"

	^ aMethod ast statements size = 1
		and: [ aMethod ast statements first isReturn
				and: [ aMethod ast statements first value isVariable ] ]
]

{ #category : 'as yet unclassified' }
BeamCodeVisualizer >> isSimpleSetter: aMethod [
	"Only a method directly returning an instance variable"

	^ aMethod ast statements size = 1
		and: [ aMethod ast statements first isAssignment
				and: [ aMethod ast statements first variable isVariable ] ]
]

{ #category : 'as yet unclassified' }
BeamCodeVisualizer >> packageViewIncluding: aClass [
	| view tags |
	view := GtMondrian new.
	tags := (RPackageOrganizer default globalPackageOf: aClass) classTags
			removeAllSuchThat: [ :e | e name = 'Manifest' ].
	view nodes
		shape: [ :each | GtMondrianUMLClassElement withDefaultContainer label: each name asString ];
		with: tags;
		forEach: [ :tag | 
				view nodes
					shape: [ :cl | 
						GtMondrianUMLClassElement withDefaultContainer
							label: cl asString;
							labelAttributes: {BlTextForegroundAttribute paint: (self colorForClass: cl)} ];
					with: (tag classes sorted: [ :a :b | a name < b name ]);
					forEach: [ :cla | 
						view nodes
							shape: [ :me | 
								BlElement new
									background: (self colorForMethod: me);
									border: (me isClassSide
											ifFalse: [ BlBorder paint: Color gray ]
											ifTrue: [ BlBorder paint: Color red ]);
									size: (5 max: 2 * me linesOfCode) @ (5 max: 2 * me numLiterals);
									margin: (BlInsets all: 1);
									yourself ];
							with: (cla methods sorted: [ :a :b | a size < b size ])
									, (cla class methods sorted: [ :a :b | a size < b size ]).
						view layout grid ].
				view edges connectFrom: #superclass ]
			in: #default.
	view layout rectanglePack.
	^ view
]
