Class {
	#name : 'ElixirFunctionCoderRowElement',
	#superclass : 'GtExpandableSourceCoderElement',
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'hooks' }
ElixirFunctionCoderRowElement >> onCollapsed [
	"Re-tint the sidebar after collapsing — same reason as onExpanded:
	 the framework's re-style overwrites our pink with grey."
	super onCollapsed.
	self enqueueTask: (BlTaskAction new
		action: [ self updateSidebarTint ])
]

{ #category : 'hooks' }
ElixirFunctionCoderRowElement >> onExpanded [
	"Re-tint the sidebar after expansion. The framework re-styles
	 the row on each expansion, repainting the sidebar grey."
	super onExpanded.
	self enqueueTask: (BlTaskAction new
		action: [ self updateSidebarTint ])
]

{ #category : 'hooks' }
ElixirFunctionCoderRowElement >> onPostTextualCoderViewModelChanged [
	"After the view model is bound, tint the row's left sidebar
	 a soft pink for macro-generated functions (hasSource = false).
	 The paint is deferred via enqueueTask: because GT's framework
	 paints the sidebar grey on a later pulse — running our paint
	 immediately gets overwritten."
	super onPostTextualCoderViewModelChanged.
	self enqueueTask: (BlTaskAction new
		action: [ self updateSidebarTint ])
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
