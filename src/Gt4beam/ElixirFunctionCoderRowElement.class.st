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
	"Paint #sidebar pink for macro-generated coders (hasSource = false),
	 framework grey otherwise.  We must explicitly set the grey on
	 has-source rows because BrSimpleList recycles row elements: a
	 row that was previously painted pink (when bound to a no-source
	 VM) needs its pink cleared when rebound to a has-source VM,
	 not just left alone."
	self hasTextualCoderViewModel ifFalse: [ ^ self ].
	self
		childNamed: #sidebar
		ifFound: [ :aSidebar |
			aSidebar background: (self textualCoderViewModel coder hasSource
				ifTrue: [ self theme button defaultBorderColor ]
				ifFalse: [ Color fromHexString: 'FFE0E6' ]) ]
		ifNone: [  ]
]
