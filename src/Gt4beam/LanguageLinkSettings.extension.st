Extension { #name : 'LanguageLinkSettings' }

{ #category : '*Gt4beam' }
LanguageLinkSettings class >> elixirDefaultSettings [
	^ self new
		clientSocketAddress: (LanguageLinkSocketAddress ipOrName: 'localhost' port: 9000 + 99 atRandom);
		serverSocketAddress: (LanguageLinkSocketAddress ipOrName: 'localhost' port: 9900 + 99 atRandom);
		messageBrokerStrategy: BeamLinkHttpMessageBroker;
		serverProcessClass: BeamLinkBeamProcess;
		platform: BeamPlatform new;
		commandFactoryClass: BeamLinkCommandFactory;
		commandClass: ElixirLinkCommand;
		serializerClass: LanguageLinkSerializer;
		deserializerClass: BeamLinkDeserializer;
		parserClass: ElixirParser;
		yourself
]
