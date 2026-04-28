"
I model a wrench-icon dropdown that gets appended after a module-
name reference whose module isn't loaded in the running BEAM.
Click the wrench to open a small actions menu (today just 'Create
module', which scaffolds `lib/<snake>/<...>.ex` via
`GtBridge.ModuleCreator.create/1` and recompiles).

I am NOT a `BrTextAdornmentAttribute` subclass.  Earlier I tried to
be one and override `doAffect:in:`, but that semantic *replaces*
the underlying character with the button instead of appending the
button after it.  The styler uses my class-side factory
`forModule:application:` instead, which returns a properly
configured `BrTextAdornmentDynamicAttribute beAppend; stencil:`
that wraps my `buildButton`.

Modeled on `GtFixItAttribute` (same icon, same aptitude composition,
same explicit-dropdown wiring) and on `ElixirFunctionExpanderAttribute`
(same beAppend stencil pattern).  Mirrors the canonical Smalltalk
'unknown class name → fix-it menu' affordance.
"
Class {
	#name : 'ElixirUnknownModuleAttribute',
	#superclass : 'Object',
	#instVars : [
		'targetModule',
		'application'
	],
	#category : 'Gt4beam',
	#package : 'Gt4beam'
}

{ #category : 'instance creation' }
ElixirUnknownModuleAttribute class >> forModule: aModuleName application: anApp [
	"I return a `BrTextAdornmentDynamicAttribute` configured to
	 append a wrench-icon button after the source character it's
	 attached to.  The button (built lazily by my stencil) opens
	 a dropdown of module-scoped actions; today just 'Create module'.

	 Use me from a styler:
	   self attribute: (ElixirUnknownModuleAttribute
	     forModule: name application: app)
	   from: endPos to: endPos."
	| model |
	model := self new
		targetModule: aModuleName application: anApp;
		yourself.
	^ BrTextAdornmentDynamicAttribute new
		beAppend;
		stencil: [ model buildButton ]
]

{ #category : 'private' }
ElixirUnknownModuleAttribute >> buildButton [
	"I return the wrench-icon button with the actions dropdown."
	| button |
	button := BrButton new
		beTinySize;
		aptitude:
			BrGlamorousButtonWithIconAptitude
			- BrGlamorousButtonExteriorAptitude
			- BrGlamorousButtonWithLabelTooltipAptitude2;
		icon: BrGlamorousVectorIcons repair;
		yourself.
	button addAptitude: (BrGlamorousWithExplicitDropdownAptitude
		handle: [
			BrButton new
				beTinySize;
				aptitude:
					BrGlamorousButtonWithIconAptitude
					- BrGlamorousButtonExteriorAptitude
					- BrGlamorousButtonWithLabelTooltipAptitude2;
				icon: BrGlamorousVectorIcons repair;
				yourself ]
		content: [ self buildMenuContent ]).
	button addAptitude:
		(BrGlamorousWithExplicitTooltipAptitude
			text: 'Module ', targetModule, ' is not defined').
	^ button
]

{ #category : 'private' }
ElixirUnknownModuleAttribute >> buildMenuContent [
	"I return the dropdown body — vertical list of actions.  Add
	 entries here as more module-scoped actions land (rename,
	 browse references, etc.)."
	^ BrVerticalPane new
		fitContentLimited;
		padding: (BlInsets all: 4);
		addChild: (self
			menuItemLabel: 'Create module ', targetModule
			action: [ self createTargetModule ]);
		yourself
]

{ #category : 'private' }
ElixirUnknownModuleAttribute >> createTargetModule [
	"I write a fresh `defmodule targetModule do; end` to disk,
	 recompile, and announce the BEAM-side recompile events on the
	 GT-side bus so per-module caches (`BeamModuleResolution`,
	 `BeamModuleSourceCache`) learn about the new module without
	 waiting for the next save.  Without this fan-out the wrench
	 stays visible until the user manually triggers a re-style
	 against a refreshed cache.

	 Mirrors the saveAndCompile flow's
	 `ElixirModuleCoder>>announceBeamRecompiledFrom:`.

	 Errors (`{:error, :exists}` / `{:error, :not_elixir_module}`)
	 come back as a `BeamTupleObject` proxy instead of a `Map`
	 proxy; we detect that by the absence of `:recompiled` on the
	 response and skip the fan-out silently."
	| result recompiled |
	result := application evaluateAndWait:
		'GtBridge.ModuleCreator.create(', targetModule, ')'.
	(result respondsTo: #attributeAt:) ifFalse: [ ^ self ].
	recompiled := result attributeAt: #recompiled.
	recompiled ifNil: [ ^ self ].
	recompiled asList do: [ :modPayload |
		BeamEventAnnouncer announceRecompiledFrom: modPayload ]
]

{ #category : 'private' }
ElixirUnknownModuleAttribute >> menuItemLabel: aLabel action: anAction [
	"I return a single menu-row button that hides the parent dropdown
	 before invoking its action — matches GT's fix-it menu behaviour."
	^ BrButton new
		aptitude: BrGlamorousButtonWithLabelAptitude;
		label: aLabel;
		action: [ :btn |
			btn fireEvent: BrDropdownHideWish new.
			anAction value ]
]

{ #category : 'accessing' }
ElixirUnknownModuleAttribute >> targetModule: aModuleName application: anApp [
	targetModule := aModuleName.
	application := anApp
]
