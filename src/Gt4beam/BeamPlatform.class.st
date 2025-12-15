Class {
	#name : 'BeamPlatform',
	#superclass : 'LanguageLinkPlatform',
	#category : 'Gt4beam-Processes',
	#package : 'Gt4beam',
	#tag : 'Processes'
}

{ #category : 'hooks' }
BeamPlatform class >> weakRegistryClass [
	^ LanguageLinkPharoWeakRegistry
]

{ #category : 'hooks' }
BeamPlatform >> ensureEnvironmentForApp: anApplication [
	"TODO: See how best to not run this
 	TODO: See what has to change on Windows"

	[ | proc error |
	proc := GtSubprocessWithInMemoryOutput new
			shellCommand: 'mix deps.get';
			workingDirectory: anApplication workingDirectory;
			runAndWait.
	proc isSuccess
		ifFalse: [ error := LanguageLinkProcessError new
					messageText: 'Unable to fetch dependencies for the bridge';
					application: anApplication;
					process: proc.
			error signal ] ] asJob
		title: 'Updating the Mix Dependencies';
		run
]

{ #category : 'accessing' }
BeamPlatform >> folderForApplication [
	^ self class package repository repository location
]

{ #category : 'utils' }
BeamPlatform >> newRandomName [
	^ 'beam' , UUID new asString36
]
