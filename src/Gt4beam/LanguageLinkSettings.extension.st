Extension { #name : 'LanguageLinkSettings' }

{ #category : '*Gt4beam' }
LanguageLinkSettings class >> elixirDefaultSettings [
	"Spawn a fresh BEAM on a random high port — the standalone default
	 when no running bridge is being connected to."
	^ self elixirDefaultSettings: 9900 + 99 atRandom
]

{ #category : '*Gt4beam' }
LanguageLinkSettings class >> elixirDefaultSettings: aServerPort [
	"The BEAM framed-TCP transport settings, connecting on `aServerPort`.
	 One full-duplex socket carries both evals and events, so there is no
	 separate client port.  The single source of these settings:
	 `elixirDefaultSettings` and `BeamLinkApplication connectwithServerPort:`
	 both come through here."
	^ self new
		serverSocketAddress: (LanguageLinkSocketAddress ipOrName: 'localhost' port: aServerPort);
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
