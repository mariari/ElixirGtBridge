"
I am a bridge value that was materialised rather than proxied, and I
answer the same reading protocol as {{gtClass:BeamProxyObject}} so
callers cannot tell the difference.

`BeamProxyObject >> asList` fetches a whole remote list in one call
instead of one call per element.  The elements come back as ordinary
Dictionaries and Arrays, which do not understand `attributeAt:`,
`itemAt:`, or `length`.  Rather than extend those system classes for a
problem that belongs to this package, I wrap them.

I wrap what I return, so a nested read stays in the protocol:

    (entry attributeAt: #children) asList

Scalars are never wrapped; they pass through as ordinary Smalltalk
objects, so leaves stay Strings and Integers.
"
Class {
	#name : 'BeamValue',
	#superclass : 'Object',
	#instVars : [
		'value'
	],
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'instance creation' }
BeamValue class >> wrapping: aValue [
	"I wrap only what needs the proxy protocol.  Scalars pass through
	 untouched so leaves stay ordinary Smalltalk objects."
	^ (aValue isDictionary or: [ aValue isArray ])
		ifTrue: [ self new setValue: aValue ]
		ifFalse: [ aValue ]
]

{ #category : 'converting' }
BeamValue >> asList [
	"I am already materialised; hand back my elements wrapped so they
	 answer the same protocol."
	^ value collect: [ :each | BeamValue wrapping: each ]
]

{ #category : 'accessing' }
BeamValue >> attributeAt: aKey [
	"Keys are normalised to strings because the wire form carries them
	 as strings while callers pass symbols."
	^ BeamValue wrapping: (value at: aKey asString ifAbsent: [ nil ])
]

{ #category : 'accessing' }
BeamValue >> itemAt: anIndex [
	"0-based, matching `BeamProxyObject >> itemAt:`, which maps to
	 Elixir's `elem/2`."
	^ BeamValue wrapping: (value at: anIndex + 1)
]

{ #category : 'accessing' }
BeamValue >> length [
	^ value size
]

{ #category : 'printing' }
BeamValue >> printOn: aStream [
	aStream nextPutAll: 'a BeamValue'; print: value
]

{ #category : 'private' }
BeamValue >> setValue: aValue [
	value := aValue.
	^ self
]

{ #category : 'accessing' }
BeamValue >> value [
	"My underlying Dictionary or Array, for callers that want the raw
	 materialised form."
	^ value
]
