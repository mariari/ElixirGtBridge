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
	#category : 'Gt4beam-Styler',
	#package : 'Gt4beam',
	#tag : 'Styler'
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
	| nameField appField createButton form completionController |
	nameField := self formEditorWithText: targetModule.
	appField := self formEditorWithText: self defaultApp asString.
	completionController := GtCompletionController
		on: appField
		strategy: (BeamAppCompletionStrategy new apps: self projectApps).
	completionController install.
	completionController showOnTextModification: true.
	appField when: BlFocusInEvent do: [ :evt |
		completionController startCompletionAt: 0 ].
	createButton := BrButton new
		aptitude: BrGlamorousButtonWithLabelAptitude;
		label: 'Create';
		action: [ :btn |
			btn fireEvent: BrDropdownHideWish new.
			self
				createTargetModuleNamed: nameField text asString trimBoth
				in: appField text asString trimBoth ].
	form := BrVerticalPane new
		fitContentLimited;
		padding: (BlInsets all: 8);
		addChild: (self labeledRow: 'Module:' field: nameField);
		addChild: (self labeledRow: 'App:' field: appField);
		addChild: (BrHorizontalPane new
			hMatchParent;
			vFitContent;
			alignCenterRight;
			margin: (BlInsets top: 6);
			addChild: createButton;
			yourself);
		yourself.
	^ form
]

{ #category : 'private' }
ElixirUnknownModuleAttribute >> createTargetModuleNamed: aModuleName in: anAppName [
	"Errors (`{:error, :exists | :not_elixir_module | :unknown_app}`)
	 come back as BeamTupleObject; the bridge fires no event for them
	 and the wrench stays visible."
	| sanitizedApp |
	sanitizedApp := anAppName
		select: [ :ch | ch isLetter or: [ ch isDigit or: [ ch = $_ ] ] ].
	(aModuleName isEmpty or: [ sanitizedApp isEmpty ]) ifTrue: [ ^ self ].
	application evaluateAndWait:
		'GtBridge.ModuleCreator.create(', aModuleName, ', :', sanitizedApp, ')'
]

{ #category : 'accessing' }
ElixirUnknownModuleAttribute >> defaultApp [
	"`Atom.to_string` on the BEAM side ensures we cross as a String,
	 not a BeamAtomObject (whose printString includes a `#` prefix)."
	^ ([ application evaluateAndWait: 'Mix.Project.config()[:app] |> Atom.to_string' ]
		on: Error do: [ nil ]) ifNil: [ '' ]
]

{ #category : 'private' }
ElixirUnknownModuleAttribute >> formEditorWithText: aString [
	"Default `BrGlamorousEditorAptitude` paints text with no border
	 or background; without affordance the field looks unclickable."
	^ BrEditor new
		aptitude: (BrGlamorousEditorAptitude new glamorousCodeFont; fontSize: 12);
		text: aString;
		hMatchParent;
		vFitContent;
		padding: (BlInsets all: 4);
		background: (Color fromHexString: 'F5F5F5');
		border: (BlBorder paint: (Color gray alpha: 0.4) width: 1)
]

{ #category : 'private' }
ElixirUnknownModuleAttribute >> labeledRow: aLabel field: aField [
	^ BrHorizontalPane new
		hMatchParent;
		vFitContent;
		alignCenterLeft;
		margin: (BlInsets bottom: 4);
		addChild: (BrLabel new
			aptitude: BrGlamorousLabelAptitude;
			text: aLabel;
			margin: (BlInsets right: 6);
			constraintsDo: [ :c | c linear horizontal alignCenter ]);
		addChild: aField;
		yourself
]

{ #category : 'accessing' }
ElixirUnknownModuleAttribute >> projectApps [
	"Main project + path-dep apps as Strings, for the App field's
	 autocomplete.  Falls back to [defaultApp] on bridge error."
	^ [ | result list |
		result := application evaluateAndWait:
			'GtBridge.ModuleCreator.project_apps() |> Enum.map(&Atom.to_string/1)'.
		list := (result respondsTo: #asList) ifTrue: [ result asList ] ifFalse: [ result ].
		list collect: [ :each | each asString ] ]
		on: Error do: [ { self defaultApp asString } ]
]

{ #category : 'accessing' }
ElixirUnknownModuleAttribute >> targetModule: aModuleName application: anApp [
	targetModule := aModuleName.
	application := anApp
]
