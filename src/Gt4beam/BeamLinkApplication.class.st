Class {
	#name : 'BeamLinkApplication',
	#superclass : 'LanguageLinkApplication',
	#category : 'Gt4beam-Global',
	#package : 'Gt4beam',
	#tag : 'Global'
}

{ #category : 'accessing' }
BeamLinkApplication class >> connectwithServerPort: server [
	"Connect over the framed TCP transport on `server`.  There is no
	 client port: the socket is full-duplex, so replies and events come
	 back on the connection I open."
	^ self
		startWith: (LanguageLinkSettings new
				serverSocketAddress: (LanguageLinkSocketAddress ipOrName: 'localhost' port: server);
				messageBrokerStrategy: BeamLinkTcpMessageBroker;
				serverProcessClass: BeamLinkBeamProcess;
				platform: BeamPlatform new;
				commandFactoryClass: BeamLinkCommandFactory;
				commandClass: ElixirLinkCommand;
				serializerClass: LanguageLinkSerializer;
				deserializerClass: BeamLinkDeserializer;
				parserClass: ElixirParser;
				yourself)
]

{ #category : 'start - stop' }
BeamLinkApplication class >> start [
	"We use startWith: however I need to override that to allow multiple toggleable instances"

	^ self startWith: LanguageLinkSettings elixirDefaultSettings
]

{ #category : 'as yet unclassified' }
BeamLinkApplication >> gtCoderBrowserFor: aView [
	<gtView>
	<gtBeamView>
	self isRunning ifFalse: [ ^ aView empty ].
	^ aView explicit
		title: 'Code Browser';
		priority: 8;
		stencil: [ ElixirCoderBrowser forApplication: self ]
]

{ #category : 'initialization' }
BeamLinkApplication >> initializeHandlers [
	loggingHandler := LanguageLinkLoggingHandler application: self.
	processHandler := LanguageLinkServerHandler application: self.
	communicationHandler := LanguageLinkCommunicationHandler application: self.
	executionHandler := ElixirExecutionHandler application: self
]

{ #category : 'initialization' }
BeamLinkApplication >> postInitialization [
	"Module events feed BeamEventAnnouncer and the per-module caches
	 (cache -> SourceChanged -> coder refresh); without this the
	 event-driven UI is dead on first boot.  The broker reads events off
	 its socket, so I hand it the dispatcher."
	self settings messageBroker eventReader: (BeamEventStreamReader for: self)
]

{ #category : 'accessing' }
BeamLinkApplication >> remShInfo [
	^ self processHandler processCommandLineString
]

{ #category : 'start - stop' }
BeamLinkApplication >> stop [
	"The broker owns the socket the events came in on; stopping the
	 handlers (super) closes it, so there is nothing else to stop."
	super stop
]

{ #category : 'directory' }
BeamLinkApplication >> workingDirectory [
	^ self settings workingDirectory
]
