Class {
	#name : 'LeElixirApplicationStrategy',
	#superclass : 'LeExternalServerStrategy',
	#category : 'Gt4beam-Lepiter',
	#package : 'Gt4beam',
	#tag : 'Lepiter'
}

{ #category : 'accessing' }
LeElixirApplicationStrategy class >> strategyName [

	^ #global
]

{ #category : 'accessing' }
LeElixirApplicationStrategy >> applicationServer [
	BeamLinkApplication isRunning
		ifFalse: [ BeamLinkApplication uniqueInstance
				ifNil: [ BeamLinkApplication uniqueInstance: self newApplication ] ].
	^ BeamLinkApplication uniqueInstance
]

{ #category : 'accessing' }
LeElixirApplicationStrategy >> applicationSettings [
	"Answer the settings that will be used by the server.
	This musn't actually start the server as that should be deferred until a snippet is evaluated for the first time."

	^ BeamLinkApplication isRunning ifTrue:
		[ BeamLinkApplication uniqueInstance settings ]
	ifFalse:
		[ BeamLinkApplication defaultSettings ]
]

{ #category : 'accessing' }
LeElixirApplicationStrategy >> newApplication [
	^ BeamLinkApplication start
]

{ #category : 'accessing' }
LeElixirApplicationStrategy >> updatedSettings: applicationSettings [
	"Update the supplied settings with the lepiter configuration"
	| lepiterSettings lepiterDatabase pbDir |

	lepiterDatabase := content database.
	lepiterSettings := lepiterDatabase properties pythonBridgeSettings.
	lepiterSettings directory ifNotNil:
		[ :relativeDir | 
			pbDir := lepiterDatabase localStoreRootDirectory resolve: relativeDir.
			applicationSettings workingDirectory: pbDir ].
	lepiterSettings pipenvPath ifNotNil:
		[ :pipenvPath | applicationSettings pipenvPath: pipenvPath ].
	applicationSettings serverDebugMode: lepiterSettings serverDebugMode.
	^ applicationSettings
]
