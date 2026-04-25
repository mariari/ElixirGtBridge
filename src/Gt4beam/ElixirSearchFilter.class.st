Class {
	#name : 'ElixirSearchFilter',
	#superclass : 'GtSearchFilter',
	#instVars : [
		'title',
		'items',
		'application'
	],
	#category : 'Gt4beam',
	#package : 'Gt4beam'
}

{ #category : 'accessing' }
ElixirSearchFilter >> = anObject [
	^ self class = anObject class
		and: [ title = anObject gtDisplayString ]
]

{ #category : 'accessing' }
ElixirSearchFilter >> defaultFilterScope [
	^ items asAsyncStream
]

{ #category : 'comparing' }
ElixirSearchFilter >> hash [
	^ self class hash bitXor: title hash
]

{ #category : 'printing' }
ElixirSearchFilter >> gtDisplayOn: stream [
	stream nextPutAll: title
]

{ #category : 'views' }
ElixirSearchFilter >> gtItemsFor: aView [
	<gtView>
	<gtToolView>
	^ aView explicit
		title: 'Results';
		priority: 10;
		stencil: [
			| streaming vm |
			streaming := ElixirFilterStreamingModel new
				items: items application: application.
			vm := GtStreamingCodersViewModel new
				streamingCodersModel: streaming.
			streaming refreshItemsStreamDueTo: 'filter'.
			ElixirFunctionStreamingElement new
				streamingCodersViewModel: vm ]
]

{ #category : 'accessing' }
ElixirSearchFilter >> matches: anObject [
	^ true
]

{ #category : 'accessing' }
ElixirSearchFilter >> title: aString items: aCollection application: anApp [
	title := aString.
	items := aCollection.
	application := anApp
]
