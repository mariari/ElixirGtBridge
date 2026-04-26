"
I am the abstract base for BEAM module-event announcements published by
BeamEventAnnouncer.

I carry the module name (`mod`) common to every module-scoped event.
Subclasses add per-event payload (e.g. source hash, compile errors).

Subscribers that want every module event regardless of kind:

    BeamEventAnnouncer default
        when: BeamModuleAnnouncement
        do: [ :ann | ... ]
        for: self.
"
Class {
	#name : 'BeamModuleAnnouncement',
	#superclass : 'Announcement',
	#instVars : [ 'mod' ],
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}

{ #category : 'instance creation' }
BeamModuleAnnouncement class >> mod: aSymbol [
	^ self new
		mod: aSymbol;
		yourself
]

{ #category : 'accessing' }
BeamModuleAnnouncement >> mod [
	^ mod
]

{ #category : 'accessing' }
BeamModuleAnnouncement >> mod: aSymbol [
	mod := aSymbol
]
