Extension { #name : 'LanguageLinkSettings' }

{ #category : '*Gt4beam' }
LanguageLinkSettings class >> elixirDefaultSettings [
	^ self new
		serverSocketAddress: (LanguageLinkSocketAddress ipOrName: 'localhost' port: 9900 + 99 atRandom);
		messageBrokerStrategy: BeamLinkTcpMessageBroker;
		serverProcessClass: BeamLinkBeamProcess;
		platform: BeamPlatform new;
		commandFactoryClass: BeamLinkCommandFactory;
		commandClass: ElixirLinkCommand;
		serializerClass: LanguageLinkSerializer;
		deserializerClass: BeamLinkDeserializer;
		parserClass: ElixirParser;
		yourself
]
