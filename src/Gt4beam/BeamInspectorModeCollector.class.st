Class {
	#name : 'BeamInspectorModeCollector',
	#superclass : 'GtPhlowCollector',
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'collecting' }
BeamInspectorModeCollector >> buildSelfMode [
	"I create the implicit self mode for the inspected object."
	^ BeamInspectorMode new
		name: ((self object respondsTo: #inspectorModeName)
			ifTrue: [ self object inspectorModeName ]
			ifFalse: [ 'Remote' ]);
		priority: 0;
		object: self object;
		tool: ((self object respondsTo: #gtRemoteSideInspectorTool)
			ifTrue: [ self object gtRemoteSideInspectorTool
				name: self object inspectorModeName;
				playgroundPageStrategy: LeInspectorPlaygroundProxyClassPageStrategy forRemoteProxySide;
				withLabelAndIconAptitude ]
			ifFalse: [ GtPhlowTool default object: self object ])
]

{ #category : 'collecting' }
BeamInspectorModeCollector >> collect [
	"I collect self + declared modes + transitive declared modes
	 from referenced objects. Self is implicit (priority 0).
	 Only declared modes (not self) are collected transitively."
	| allModes declared names |
	allModes := OrderedCollection with: self buildSelfMode.
	declared := self collectDeclared.
	allModes addAll: declared.
	names := (allModes collect: #name) asSet.
	declared do: [ :mode |
		(mode object notNil and: [ mode object ~~ self object ]) ifTrue: [
			| sub |
			sub := self class new fromObject: mode object.
			sub collectDeclared do: [ :s |
				(names includes: s name) ifFalse: [
					names add: s name.
					allModes add: s ] ] ] ].
	^ allModes sorted: [ :a :b | a priority < b priority ]
]

{ #category : 'collecting' }
BeamInspectorModeCollector >> collectDeclared [
	"I collect only explicitly declared modes from pragmas."
	| modes |
	modes := self collectPragmas collect: [ :eachPragma |
		| mode |
		mode := BeamInspectorMode empty.
		[ mode := self object
			perform: eachPragma methodSelector
			with: mode ]
			on: Error do: [ :e | mode ].
		mode ].
	^ modes reject: [ :m | m isEmpty ]
]

{ #category : 'defaults' }
BeamInspectorModeCollector >> defaultPragmaNames [
	^ #( gtInspectorMode )
]
