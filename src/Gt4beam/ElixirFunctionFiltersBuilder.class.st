Class {
	#name : 'ElixirFunctionFiltersBuilder',
	#superclass : 'Object',
	#instVars : [
		'coders'
	],
	#category : 'Gt4beam-Filters',
	#package : 'Gt4beam',
	#tag : 'Filters'
}

{ #category : 'accessing' }
ElixirFunctionFiltersBuilder >> availableFilters [
	"All Elixir function filters' descriptor-2 models, sorted by order (the + menu source)."
	| available |
	coders ifNil: [ ^ #() ].
	available := SortedCollection sortBlock: [ :a :b | a order < b order ].
	ElixirFunctionsFilter withAllSubclassesDo: [ :each |
		each filterDescriptors2For: coders into: available ].
	^ available
]

{ #category : 'accessing' }
ElixirFunctionFiltersBuilder >> coders [
	^ coders
]

{ #category : 'accessing' }
ElixirFunctionFiltersBuilder >> coders: aCoders [
	coders := aCoders
]
