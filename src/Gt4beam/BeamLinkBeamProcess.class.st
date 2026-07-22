Class {
	#name : 'BeamLinkBeamProcess',
	#superclass : 'LanguageLinkAbstractProcess',
	#instVars : [
		'process'
	],
	#category : 'Gt4beam-Processes',
	#package : 'Gt4beam',
	#tag : 'Processes'
}

{ #category : 'accessing' }
BeamLinkBeamProcess >> commandLineString [
	^ process commandLineString
]

{ #category : 'gtViews' }
BeamLinkBeamProcess >> gtViewDetailsIn: composite [
	<gtView>
	<gtBeamView>
	^ composite columnedList
		title: 'Details';
		priority: 40;
		items: [ {{'running'.
					self isRunning}.
				{'server address'.
					self application settings serverSocketAddress}.
				{'debug mode'.
					self debugMode}} ];
		column: 'Key'
			text: #first
			weight: 0.5;
		column: 'Value' text: #second;
		send: #last;
		actionUpdateButton
]

{ #category : 'testing' }
BeamLinkBeamProcess >> hasProcess [
	"Answer a boolean indicating whether the receiver has a process object"

	^ process isNotNil
]

{ #category : 'testing' }
BeamLinkBeamProcess >> isRunning [
	^ process notNil and: [ process isRunning ]
]

{ #category : 'private' }
BeamLinkBeamProcess >> newProcess [
	^ GtSubprocessWithInMemoryOutput new
		workingDirectory: self workingDirectory fullName;
		command: 'iex';
		arguments: self processArguments;
		yourself
]

{ #category : 'private' }
BeamLinkBeamProcess >> processArguments [
	| arguments |
	arguments := OrderedCollection new.

	arguments
		add: '--sname';
		add: 'glam';
		add: '--cookie';
		add: 'glam';
		add: '-S';
		add: 'mix'.
	^ arguments
]

{ #category : 'start-stop' }
BeamLinkBeamProcess >> start [
	process := self newProcess.
	process run.
	process stdinStream
		nextPutAll: 'Elixir.Logger.configure(level: :debug)';
		lf.
	self
		startBridgeAt: self application settings serverSocketAddress port asString
		andClient: self application settings clientSocketAddress port asString
]

{ #category : 'start-stop' }
BeamLinkBeamProcess >> startBridgeAt: server andClient: client [
	"Bring both transports up through the bridge's transport-neutral
	 entry point; the framed TCP transport is the default, the HTTP
	 server carries the channels not yet moved over."
	process stdinStream
		nextPutAll: (String
				streamContents: [ :stream |
					stream
						nextPutAll: 'GtBridge.start_listener(';
						nextPutAll: server;
						nextPut: $,;
						nextPutAll: client;
						nextPut: $);
						lf ])
]

{ #category : 'start-stop' }
BeamLinkBeamProcess >> stop [
	process ifNil: [ ^ self ].
	process terminate.
	process := nil
]

{ #category : 'as yet unclassified' }
BeamLinkBeamProcess >> workingDirectory [
	^ application settings workingDirectory
]
