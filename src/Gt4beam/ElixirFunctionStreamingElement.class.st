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
	"I scroll the list to the matching coder VM."
	anAnnouncement scrollTarget ifNotNil: [ :aTarget |
		list scrollToItemSuchThat: [ :each | aTarget applicableTo: each ] offset: 0 ]
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
