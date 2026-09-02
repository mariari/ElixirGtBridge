"
I demonstrate the module coder's two levels: the plain coder at
normal, the module browser at detailed, as the pager maximizer flips.
"
Class {
	#name : 'ElixirCoderBrowserExamples',
	#superclass : 'Object',
	#category : 'Gt4beam-Examples',
	#package : 'Gt4beam',
	#tag : 'Examples'
}

{ #category : 'examples' }
ElixirCoderBrowserExamples >> ancestorDetailStateReachesANestedCoderElement [
	"A tool wrapper gaining the detailed state, as maximizing a nested
	 tool arranges, flips an element with no own level state; restoring
	 re-parents the subtree, as the maximizer does, and flips it back."

	<gtExample>
	| element wrapper space showsBrowser |
	element := ElixirModuleCoderElement new coderViewModel:
		(ElixirModuleCoder new moduleName: 'Up.Mid.Leaf') asCoderViewModel.
	wrapper := BlElement new
		constraintsDo: [ :c | c horizontal matchParent. c vertical matchParent ];
		addChild: element;
		yourself.
	space := BlSpace new.
	space root addChild: wrapper.
	space pulse.
	showsBrowser := [ element children anySatisfy: [ :c | c isKindOf: ElixirCoderBrowser ] ].
	self assert: showsBrowser value not.
	wrapper states addState: GtPhlowToolDetailState detailed.
	wrapper removeFromParent.
	space root addChild: wrapper.
	space pulse.
	self assert: showsBrowser value.
	wrapper states
		stateLike: GtPhlowToolDetailState normal
		ifFound: [ :aState | wrapper states removeState: aState ]
		ifNone: [  ].
	wrapper removeFromParent.
	space root addChild: wrapper.
	space pulse.
	self assert: showsBrowser value not.
	^ element
]

{ #category : 'examples' }
ElixirCoderBrowserExamples >> moduleCoderElementFlipsToBrowserWhenDetailed [
	"beDetailedLevel, as the maximizer sends, swaps my content to the
	 module browser; beNormalLevel swaps back."

	<gtExample>
	| element showsBrowser |
	element := ElixirModuleCoderElement new coderViewModel:
		(ElixirModuleCoder new moduleName: 'Up.Mid.Leaf') asCoderViewModel.
	showsBrowser := [ element children anySatisfy: [ :c | c isKindOf: ElixirCoderBrowser ] ].
	self assert: showsBrowser value not.
	element beDetailedLevel.
	self assert: showsBrowser value.
	element beNormalLevel.
	self assert: showsBrowser value not.
	^ element
]

{ #category : 'examples' }
ElixirCoderBrowserExamples >> coderElementInsideABrowserNeverFlips [
	"The browser embeds inspectors whose coders would otherwise see the
	 maximizer's detailed state and embed browsers without end."

	<gtExample>
	| element browser space |
	element := ElixirModuleCoderElement new coderViewModel:
		(ElixirModuleCoder new moduleName: 'Up.Mid.Leaf') asCoderViewModel.
	browser := ElixirCoderBrowser forApplication: nil.
	browser addChild: element.
	space := BlSpace new.
	space root addChild: browser.
	space root states addState: GtPhlowToolDetailState detailed.
	space pulse.
	self assert: (element children anySatisfy: [ :c | c isKindOf: ElixirCoderBrowser ]) not.
	element beDetailedLevel.
	self assert: (element children anySatisfy: [ :c | c isKindOf: ElixirCoderBrowser ]) not.
	^ element
]

{ #category : 'examples' }
ElixirCoderBrowserExamples >> theSameCoderPaneTravelsIntoTheBrowserAndBack [
	"The browser hosts the live coder pane rather than a fresh embed, so
	 expanded rows, scroll and unsaved edits survive the flip both ways."

	<gtExample>
	| element pane inBrowser |
	element := ElixirModuleCoderElement new coderViewModel:
		(ElixirModuleCoder new moduleName: 'Up.Mid.Leaf') asCoderViewModel.
	pane := element children first.
	element beDetailedLevel.
	inBrowser := false.
	(element children detect: [ :c | c isKindOf: ElixirCoderBrowser ] ifNone: [ nil ])
		ifNotNil: [ :browser |
			browser allChildrenBreadthFirstDo: [ :c | c == pane ifTrue: [ inBrowser := true ] ] ].
	self assert: inBrowser.
	element beNormalLevel.
	self assert: (element children includes: pane).
	^ element
]

{ #category : 'examples' }
ElixirCoderBrowserExamples >> restoreFollowsTheModuleChosenInTheBrowser [
	"Clicking another module while maximized retargets the half view:
	 zooming back out keeps the chosen module, not the original."

	<gtExample>
	| element browser |
	element := ElixirModuleCoderElement new coderViewModel:
		(ElixirModuleCoder new moduleName: 'Up.Mid.Leaf') asCoderViewModel.
	element beDetailedLevel.
	browser := element children detect: [ :c | c isKindOf: ElixirCoderBrowser ].
	browser focusSidebarOn: 'Up.Other'.
	element beNormalLevel.
	self assert: element coder moduleName equals: 'Up.Other'.
	self assert: (element children anySatisfy: [ :c | c isKindOf: ElixirCoderBrowser ]) not.
	^ element
]
