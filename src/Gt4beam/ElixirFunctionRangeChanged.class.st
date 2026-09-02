"
I announce, on a module coder, that the Functions-up-to range now
covers these module names. Nothing subscribes yet; Lepiter session
priming is the intended listener.
"
Class {
	#name : 'ElixirFunctionRangeChanged',
	#superclass : 'Announcement',
	#instVars : [
		'modules'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'instance creation' }
ElixirFunctionRangeChanged class >> modules: anArray [
	^ self new modules: anArray
]

{ #category : 'accessing' }
ElixirFunctionRangeChanged >> modules [
	^ modules
]

{ #category : 'accessing' }
ElixirFunctionRangeChanged >> modules: anArray [
	modules := anArray
]
