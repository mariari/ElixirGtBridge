"
I pair a function entry with the module coder it came from, so a
concatenated stream still knows where each row belongs.
"
Class {
	#name : 'ElixirRangeEntry',
	#superclass : 'Object',
	#instVars : [
		'entry',
		'moduleCoder'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'instance creation' }
ElixirRangeEntry class >> entry: anEntry moduleCoder: aModuleCoder [
	^ self new entry: anEntry moduleCoder: aModuleCoder
]

{ #category : 'accessing' }
ElixirRangeEntry >> attributeAt: aKey [
	"#module is mine; everything else is the entry's."
	aKey asString = 'module' ifTrue: [ ^ moduleCoder moduleName ].
	^ entry attributeAt: aKey
]

{ #category : 'accessing' }
ElixirRangeEntry >> entry [
	^ entry
]

{ #category : 'initialization' }
ElixirRangeEntry >> entry: anEntry moduleCoder: aModuleCoder [
	entry := anEntry.
	moduleCoder := aModuleCoder
]

{ #category : 'testing' }
ElixirRangeEntry >> isForeignTo: aModuleCoder [
	^ moduleCoder ~~ aModuleCoder
]

{ #category : 'accessing' }
ElixirRangeEntry >> moduleCoder [
	^ moduleCoder
]
