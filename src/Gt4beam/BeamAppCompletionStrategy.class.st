"
I complete app-name prefixes against a static list, used by the
wrench's Create-module form.
"
Class {
	#name : 'BeamAppCompletionStrategy',
	#superclass : 'GtStreamedCompletionStrategy',
	#instVars : [
		'apps'
	],
	#category : 'Gt4beam-Completion',
	#package : 'Gt4beam',
	#tag : 'Completion'
}

{ #category : 'accessing' }
BeamAppCompletionStrategy >> apps: aListOfStrings [
	apps := aListOfStrings asArray
]

{ #category : 'completion' }
BeamAppCompletionStrategy >> completionActionStreamFor: aText at: positionInteger requested: aBoolean [
	| prefix matches |
	prefix := (aText asString first: positionInteger) trimBoth.
	matches := apps
		select: [ :a | prefix isEmpty or: [ a asLowercase beginsWith: prefix asLowercase ] ].
	^ matches asAsyncStream
		collect: [ :each |
			GtInsertTextCompletionAction
				labeled: each
				completion: (each allButFirst: prefix size)
				position: positionInteger
				from: positionInteger - prefix size + 1 ]
]
