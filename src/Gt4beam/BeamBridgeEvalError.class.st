Class {
	#name : 'BeamBridgeEvalError',
	#superclass : 'BeamProxyObject',
	#category : 'Gt4beam-Serialization',
	#package : 'Gt4beam',
	#tag : 'Serialization'
}

{ #category : 'as yet unclassified' }
BeamBridgeEvalError class >> elixirClass [
	^ 'GtBridge.Eval.Error'
]

{ #category : 'predicates' }
BeamBridgeEvalError >> isError [
	"I am the value a failed eval answers, so I say so."
	^ true
]

{ #category : 'accessing' }
BeamBridgeEvalError >> messageText [
	"I answer the node's own one-line account of the failure.
	 Exception.format_banner covers structs, atoms, throws and exits."
	^ self evaluateAndWait:
		'(fn x -> Exception.format_banner(x.kind, x.error, x.trace) end).('
			, self resolve , ')'
]
