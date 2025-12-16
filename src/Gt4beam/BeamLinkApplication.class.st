Class {
	#name : 'BeamLinkApplication',
	#superclass : 'LanguageLinkApplication',
	#category : 'Gt4beam-Global',
	#package : 'Gt4beam',
	#tag : 'Global'
}

{ #category : 'accessing' }
BeamLinkApplication class >> connectwithServerPort: server clientPort: cleint [
	^ self
		startWith: (LanguageLinkSettings new
				clientSocketAddress: (LanguageLinkSocketAddress ipOrName: 'localhost' port: cleint);
				serverSocketAddress: (LanguageLinkSocketAddress ipOrName: 'localhost' port: server);
				messageBrokerStrategy: BeamLinkHttpMessageBroker;
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

{ #category : 'initialization' }
BeamLinkApplication >> initializeHandlers [
	loggingHandler := LanguageLinkLoggingHandler application: self.
	processHandler := LanguageLinkServerHandler application: self.
	communicationHandler := LanguageLinkCommunicationHandler application: self.
	executionHandler := ElixirExecutionHandler application: self
]

{ #category : 'as yet unclassified' }
BeamLinkApplication >> remShInfo [
^ self processHandler processCommandLineString
]

{ #category : 'directory' }
BeamLinkApplication >> workingDirectory [
	^ self settings workingDirectory
]
