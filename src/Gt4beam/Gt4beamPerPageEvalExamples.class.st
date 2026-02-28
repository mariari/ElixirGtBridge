Class {
	#name : 'Gt4beamPerPageEvalExamples',
	#superclass : 'Object',
	#category : 'Gt4beam-Examples',
	#package : 'Gt4beam',
	#tag : 'Examples'
}

{ #category : 'examples - message' }
Gt4beamPerPageEvalExamples >> messageWithSessionId [
	"I verify that encoding a message with a sessionId includes it in the dict."
	<gtExample>
	| msg dict |
	msg := ElixirLinkEnqueueCommandMessage new
		commandId: 'cmd-1';
		statements: 'x = 1';
		sessionId: 'page-abc'.
	dict := msg encode.
	self assert: (dict at: #sessionId) equals: 'page-abc'.
	self assert: (dict at: #type) equals: 'ENQUEUE'.
	^ dict
]

{ #category : 'examples - message' }
Gt4beamPerPageEvalExamples >> messageWithoutSessionId [
	"I verify that encoding a message without a sessionId omits the key entirely."
	<gtExample>
	| msg dict |
	msg := ElixirLinkEnqueueCommandMessage new
		commandId: 'cmd-2';
		statements: 'y = 2'.
	dict := msg encode.
	self assert: (dict includesKey: #sessionId) not.
	self assert: (dict at: #commandId) equals: 'cmd-2'.
	^ dict
]

{ #category : 'examples - command' }
Gt4beamPerPageEvalExamples >> commandCarriesSessionId [
	"I verify that ElixirLinkCommand stores and returns a sessionId."
	<gtExample>
	| cmd |
	cmd := ElixirLinkCommand new.
	cmd sessionId: 'page-xyz'.
	self assert: cmd sessionId equals: 'page-xyz'.
	^ cmd
]

{ #category : 'examples - command' }
Gt4beamPerPageEvalExamples >> commandSessionIdDefaultsToNil [
	"I verify that a fresh command has nil sessionId (backward compat)."
	<gtExample>
	| cmd |
	cmd := ElixirLinkCommand new.
	self assert: cmd sessionId isNil.
	^ cmd
]

{ #category : 'examples - coder model' }
Gt4beamPerPageEvalExamples >> coderModelCarriesSessionId [
	"I verify that GtElixirCoderModel stores a sessionId."
	<gtExample>
	| coder |
	coder := GtElixirCoderModel new.
	coder sessionId: 'page-123'.
	self assert: coder sessionId equals: 'page-123'.
	^ coder
]

{ #category : 'examples - coder model' }
Gt4beamPerPageEvalExamples >> coderModelSessionIdDefaultsToNil [
	"I verify that a fresh coder model has nil sessionId,
	so inspector snippets fall back to the default session."
	<gtExample>
	| coder |
	coder := GtElixirCoderModel new.
	self assert: coder sessionId isNil.
	^ coder
]

{ #category : 'examples - factory' }
Gt4beamPerPageEvalExamples >> factoryCarriesSessionId [
	"I verify that BeamLinkCommandFactory stores a sessionId."
	<gtExample>
	| factory |
	factory := BeamLinkCommandFactory new.
	factory sessionId: 'page-456'.
	self assert: factory sessionId equals: 'page-456'.
	^ factory
]

{ #category : 'examples - handler' }
Gt4beamPerPageEvalExamples >> handlerBuildsMessageWithSessionId [
	"I verify the full path: command with sessionId → handler → message
	with sessionId in the encoded dict.

	Requires a running application (handler needs serialize:).
	Skip gracefully if BeamLinkApplication is not available."
	<gtExample>
	| app handler cmd msg dict |
	[ app := BeamLinkApplication start ]
		on: Error do: [ :e | ^ 'Skipped: ' , e messageText ].
	handler := app executionHandler.
	cmd := ElixirLinkCommand new.
	cmd sessionId: 'page-integration'.
	msg := handler buildMessageFromCommand: cmd.
	dict := msg encode.
	self assert: (dict at: #sessionId) equals: 'page-integration'.
	app stop.
	^ dict
]
