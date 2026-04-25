Class {
	#name : 'ElixirFunctionStreamingElement',
	#superclass : 'BlElement',
	#traits : 'TBrLayoutResizable',
	#classTraits : 'TBrLayoutResizable classTrait',
	#instVars : [
		'listItemsProvider',
		'list',
		'streamingCodersViewModel'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'as yet unclassified' }
ElixirFunctionStreamingElement >> initialize [
	super initialize.
	self matchParent.
	listItemsProvider := BrStreamItemsProvider new stream: AsyncEmptyStream new.
	list := BrSimpleList new
		itemType: [ :anItemTypeFactory :anItemObject | anItemObject elementClass ];
		itemStencil: [ :anElementClass |
			anElementClass new
				vFitContentLimited;
				yourself ];
		itemId: [ :eachCoderViewModel | eachCoderViewModel coder id ];
		itemDataBinder: [ :aCoderElement :aCoderViewModel :anItemIndex |
			aCoderElement
				id: (GtSourceCoderId indexed: anItemIndex);
				textualCoderViewModel: aCoderViewModel ];
		itemsProvider: listItemsProvider;
		matchParent.
	self addChild: list
]

{ #category : 'as yet unclassified' }
ElixirFunctionStreamingElement >> onStreamingCodersChanged: anAnnouncement [
	listItemsProvider stream: streamingCodersViewModel coderViewModelsStream
]

{ #category : 'as yet unclassified' }
ElixirFunctionStreamingElement >> streamingCodersViewModel [
	^ streamingCodersViewModel
]

{ #category : 'as yet unclassified' }
ElixirFunctionStreamingElement >> streamingCodersViewModel: aViewModel [
	streamingCodersViewModel := aViewModel.
	self subscribeToStreamingCodersViewModel.
	"Pass current stream immediately"
	listItemsProvider stream: streamingCodersViewModel coderViewModelsStream
]

{ #category : 'as yet unclassified' }
ElixirFunctionStreamingElement >> onScrollTargetChanged: anAnnouncement [
	"I scroll to the matching coder VM AND expand+focus it. Coders
	 default to folded in this list, so a navigation target (e.g.
	 'show me string/2 in GtBridge.Phlow.Text') would otherwise land
	 on a folded row even after scrolling. The match block runs only
	 on items the scanner inspects; the side-effect fires on the
	 single item where applicableTo: returns true."
	anAnnouncement scrollTarget ifNotNil: [ :aTarget |
		list
			scrollToItemSuchThat: [ :each |
				(aTarget applicableTo: each)
					ifTrue: [
						each expanded: true.
						each focused: true.
						true ]
					ifFalse: [ false ] ]
			offset: 0 ]
]

{ #category : 'as yet unclassified' }
ElixirFunctionStreamingElement >> subscribeToStreamingCodersViewModel [
	streamingCodersViewModel
		when: GtStreamingCodersViewModelStreamChanged
		send: #onStreamingCodersChanged: to: self.
	streamingCodersViewModel
		when: GtStreamingCodersViewModelScrollTargetChanged
		send: #onScrollTargetChanged: to: self
]
