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
	#instVars : [
		'mod'
	],
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}

{ #category : 'gt-views' }
BeamModuleAnnouncement class >> gtSubscribersFor: aView [
	"I render every subscription to me (or my subclasses) across
	 every known `BeamEventAnnouncer` — the default singleton plus
	 every per-module announcer registered in the registry.

	 Open this view on any concrete event class
	 (`BeamModuleRecompiled`, `BeamModuleSourceChanged`,
	 `BeamModuleEntriesUpdated`, etc.) to see who's listening.
	 Useful for spotting unexpected receivers and for sanity-checking
	 that the cache pattern's 'one writer per derivation' property
	 still holds (only one cache class should subscribe to
	 `BeamModuleRecompiled` for each module)."

	<gtClassView>
	^ aView mondrian
		title: 'Subscribers';
		priority: 5;
		painting: [ :aMondrian |
			| nodes edges labels event announcers walk |
			nodes := OrderedCollection new.
			edges := OrderedCollection new.
			labels := IdentityDictionary new.
			event := self.

			nodes add: event.
			labels at: event put: event name.

			announcers := OrderedCollection new
				add: 'default' -> BeamEventAnnouncer default;
				yourself.
			(BeamEventAnnouncer announcers ifNil: [ Dictionary new ])
				keysAndValuesDo: [ :k :a | announcers add: k -> a ].

			walk := [ :ann :label |
				| subs matching |
				subs := [ ann subscriptions subscriptions
					ifNil: [ #() ]
					ifNotNil: [ :s | s ] ]
					on: Error do: [ #() ].
				matching := subs select: [ :sub |
					[ sub announcementClass = event
						or: [ event inheritsFrom: sub announcementClass ] ]
						on: Error do: [ false ] ].
				matching ifNotEmpty: [
					(nodes includes: ann) ifFalse: [
						nodes add: ann.
						labels at: ann put: 'announcer: ', label.
						edges add: event -> ann ].
					(matching groupedBy: [ :s | s subscriber class name ])
						keysAndValuesDo: [ :clsName :subs2 |
							| groupNode |
							groupNode := (subs2 collect: [ :s | s subscriber ]) asArray.
							nodes add: groupNode.
							labels at: groupNode
								put: clsName , ' (' , subs2 size asString , ')'.
							edges add: ann -> groupNode ] ] ].

			announcers do: [ :pair |
				walk value: pair value value: pair key asString ].

			BeamMondrianHelpers
				paintLabeledGraphOn: aMondrian
				nodes: nodes edges: edges
				labels: labels
				layout: [ :l | l horizontalTree nodeDistance: 8; levelDistance: 40 ] ]
]

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
