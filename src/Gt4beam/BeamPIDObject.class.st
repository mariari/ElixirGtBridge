Class {
	#name : 'BeamPIDObject',
	#superclass : 'BeamProxyObject',
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'dispatch' }
BeamPIDObject class >> elixirClass [
	^ 'PID'
]

{ #category : 'accessing' }
BeamPIDObject >> applicationAnalysis [
	"I find my application by PID (not by module name like proxies
	 do) using Erlang's :application.get_application/1."
	| appAtom sys |
	appAtom := [ self evaluateAndWait:
		'case :application.get_application(', self resolve, ') do
			{:ok, app} -> app
			_ -> nil
		end' ]
		on: Error do: [ nil ].
	appAtom ifNil: [ ^ nil ].
	sys := ElixirSystemAnalysis onApplication: self application.
	^ sys applications
		detect: [ :each | each name symbol = appAtom symbol ]
		ifNone: [ nil ]
]

{ #category : 'views - helpers' }
BeamPIDObject >> childrenTree [
	^ self
		evaluateAndWait: self resolve , ' |> GtBridge.ViewHelpers.build_supervision()'
]

{ #category : 'gt-thyhbb' }
BeamPIDObject >> gtActorStateFor: aView [
	<gtView>
	<gtBeamView>
	| result state attrs |
	result := self evaluateAndWait:
		'try do {:ok, :sys.get_state(' , self resolve , ', 500)} catch :exit, _ -> :error end'.
	(result isKindOf: BeamAtomObject) ifTrue: [ ^ aView empty ].
	state := result itemAt: 1.
	attrs := [ state attributesAndValues ] on: Error do: [ #() ].
	attrs isEmpty ifTrue: [ ^ aView empty ].
	^ aView columnedTree
		title: 'State';
		priority: 8;
		items: [ attrs ];
		children: [ :anItem |
			(anItem value isKindOf: BeamProxyObject)
				ifTrue: [ anItem value attributesAndValues ]
				ifFalse: [ #() ] ];
		column: 'Variable' text: #key;
		column: 'Value' text: #value;
		send: #value;
		actionUpdateButton
]

{ #category : 'gt-extensions' }
BeamPIDObject >> gtDefaultInspectorTool [
	"I collect inspector modes via <gtInspectorMode> pragmas."
	| modes |
	modes := BeamInspectorModeCollector new
		fromObject: self;
		collect.
	^ BeamProxyToggleCompositeTool fromModes: modes
]

{ #category : 'as yet unclassified' }
BeamPIDObject >> gtInformationFor: aView [
	<gtView>
	<gtBeamView>
	^ aView columnedList
		title: 'Information';
		priority: 10;
		items: [ self information associations ];
		column: 'Name'
			text: #key
			width: 150;
		column: 'Value'
			text: [ :anItem | anItem value isArray ifTrue: [ anItem value second ] ifFalse: [ anItem value ] ];
		send: #value
]

{ #category : 'inspector-modes' }
BeamPIDObject >> gtStateMode: aMode [
	<gtInspectorMode>
	| state |
	state := [ self process_state ] on: Error do: [ nil ].
	(state isNil or: [ state isError ]) ifTrue: [ ^ aMode ].
	^ aMode
		name: 'State';
		priority: 20;
		object: state;
		tool: (state gtRemoteSideInspectorTool
			name: 'State';
			playgroundPageStrategy: LeInspectorPlaygroundProxyClassPageStrategy forRemoteProxySide;
			withLabelAndIconAptitude)
]

{ #category : 'as yet unclassified' }
BeamPIDObject >> gtSupervisionView: aView [
	<gtView>
	<gtBeamView>
	self isSupervisor ifFalse: [ ^ aView empty ].
	^ aView composite
		title: 'Supervision View';
		priority: 9;
		views: {
			(aView mondrian
				title: 'Summary';
				priority: 1;
				painting: [ :aMondrian |
					| tree |
					tree := self evaluateAndWait:
						'GtBridge.Analysis.supervision_tree(', self resolve, ')'.
					BeamMondrianHelpers
						supervisionTreeOn: aMondrian from: tree poolThreshold: 12 application: self application ]).
			(aView mondrian
				title: 'Expanded';
				priority: 2;
				painting: [ :aMondrian |
					| tree |
					tree := self evaluateAndWait:
						'GtBridge.Analysis.supervision_tree(', self resolve, ')'.
					BeamMondrianHelpers
						supervisionTreeOn: aMondrian from: tree poolThreshold: 999999 application: self application ]) }
]

{ #category : 'as yet unclassified' }
BeamPIDObject >> information [
	| informationTuples |
	informationTuples := self evaluateAndWait: 'Process.info(' , self resolve , ')'.
	^ (informationTuples asList collect: [ :aTuple |
		| pair |
		pair := aTuple asList.
		pair first -> pair second ]) asDictionary
]

{ #category : 'gt-extensions' }
BeamPIDObject >> inspectorModeName [
	^ 'Pid'
]

{ #category : 'as yet unclassified' }
BeamPIDObject >> isEvaluatorProcess [
	" I determine if I'm the same process as the current evaluator.
	I can not run certain operations on myself"

	^ self evaluateAndWait: self resolve , '== self()'
]

{ #category : 'predicates' }
BeamPIDObject >> isSupervisor [
	^ self
		evaluateAndWait: self resolve , ' |> GtBridge.ViewHelpers.determine_supervisor()'
]

{ #category : 'as yet unclassified' }
BeamPIDObject >> printOn: str [
	str << (self evaluateAndWait: self resolve , '|> inspect()')
]

{ #category : 'as yet unclassified' }
BeamPIDObject >> process_state [
	^ self evaluateAndWait: self resolve , '|> :sys.get_state()'
]
