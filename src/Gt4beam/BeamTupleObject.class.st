Class {
	#name : 'BeamTupleObject',
	#superclass : 'BeamProxyObject',
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'dispatch' }
BeamTupleObject class >> elixirClass [
	^ 'Tuple'
]

{ #category : 'as yet unclassified' }
BeamTupleObject >> asElixirList [
	^ self evaluateAndWait: self resolve , '|>Tuple.to_list() '
]

{ #category : 'as yet unclassified' }
BeamTupleObject >> attributesAndValues [
	^ self asElixirList attributesAndValues
]

{ #category : 'as yet unclassified' }
BeamTupleObject >> itemAt: idx [
	^ self evaluateAndWait: self resolve , '|> elem(' , idx asString , ')'
]

{ #category : 'as yet unclassified' }
BeamTupleObject >> length [
	^ self evaluateAndWait: self resolve , '|> tuple_size()'
]
