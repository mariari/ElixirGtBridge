Class {
	#name : 'ElixirLinkCommand',
	#superclass : 'LanguageLinkCommand',
	#instVars : [
		'sessionId'
	],
	#category : 'Gt4beam-Execution',
	#package : 'Gt4beam',
	#tag : 'Execution'
}

{ #category : 'accessing' }
ElixirLinkCommand >> sessionId [
	^ sessionId
]

{ #category : 'accessing' }
ElixirLinkCommand >> sessionId: aString [
	sessionId := aString
]

{ #category : 'accessing' }
ElixirLinkCommand >> codeForRemote [
	^ Character lf join: self instructions
]

{ #category : 'visualization' }
ElixirLinkCommand >> gtViewCodeForRemoteFor: aView [
	<gtView>
	^ aView textEditor
		aptitude: BrGlamorousCodeEditorAptitude;
		styler: (BrRBTextStyler new
				isForWorkspace: true;
				yourself);
		title: 'Command string' translated;
		text: [ self codeForRemote ];
		priority: 15
]
