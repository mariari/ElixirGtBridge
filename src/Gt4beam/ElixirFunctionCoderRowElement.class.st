Class {
	#name : 'ElixirFunctionCoderRowElement',
	#superclass : 'GtExpandableSourceCoderElement',
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'hooks' }
ElixirFunctionCoderRowElement >> deferUpdateSidebarTint [
	"Schedule updateSidebarTint on the next pulse.  GT's framework
	 paints the sidebar grey on a later pulse than the lifecycle
	 hooks (bind / expand / collapse), so an immediate paint gets
	 overwritten.  Queueing via BlTaskAction lets the framework run
	 first and our paint last."
	self enqueueTask: (BlTaskAction new action: [ self updateSidebarTint ])
]

{ #category : 'hooks' }
ElixirFunctionCoderRowElement >> onCollapsed [
	super onCollapsed.
	self deferUpdateSidebarTint
]

{ #category : 'hooks' }
ElixirFunctionCoderRowElement >> onExpanded [
	super onExpanded.
	self deferUpdateSidebarTint
]

{ #category : 'hooks' }
ElixirFunctionCoderRowElement >> onPostTextualCoderViewModelChanged [
	super onPostTextualCoderViewModelChanged.
	self deferUpdateSidebarTint
]

{ #category : 'hooks' }
ElixirFunctionCoderRowElement >> updateSidebarTint [
	"Paint #sidebar to flag what kind of entry this row is at a glance:
	 light green for type entries (typedstruct t/0, @type),
	 light pink for macro-generated coders (hasSource = false),
	 framework grey for ordinary functions with source.

	 We must explicitly set the colour on every rebind because
	 BrSimpleList recycles row elements: a row that was previously
	 painted pink or green needs that paint cleared when rebound
	 to a different VM, not just left alone."
	self hasTextualCoderViewModel ifFalse: [ ^ self ].
	self
		childNamed: #sidebar
		ifFound: [ :aSidebar |
			| coder |
			coder := self textualCoderViewModel coder.
			aSidebar background: (coder isType
				ifTrue: [ Color fromHexString: 'B8E8C0' ]
				ifFalse: [ coder hasSource
					ifTrue: [ self theme button defaultBorderColor ]
					ifFalse: [ Color fromHexString: 'FFE0E6' ] ]) ]
		ifNone: [  ]
]
