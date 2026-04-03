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

{ #category : 'views - helpers' }
BeamPIDObject >> childrenTree [
	^ self
		evaluateAndWait: self resolve , ' |> GtBridge.ViewHelpers.build_supervision()'
]

{ #category : 'as yet unclassified' }
BeamPIDObject >> gtInformationFor: aView [
	<gtView>
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

{ #category : 'as yet unclassified' }
BeamPIDObject >> gtSupervisionView: aView [
	<gtView>
	self isSupervisor ifFalse: [ ^ aView empty ].
	^ aView mondrian
		title: 'Supervision View';
		priority: 9;
		painting: [ :aMondrian |
			| tree |
			tree := self evaluateAndWait:
				'GtBridge.Analysis.supervision_tree(', self resolve, ')'.
			BeamMondrianHelpers
				supervisionTreeOn: aMondrian from: tree poolThreshold: 12 ]
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

{ #category : 'as yet unclassified' }
BeamPIDObject >> stateView: aView [
	<gtView>
	| inspect |
	inspect := self process_state.
	inspect isError ifTrue: [ ^ aView empty ].

	^ aView composite
		title: 'State View';
		priority: 1;
		views: (inspect gtViewsInCurrentContext)
]
