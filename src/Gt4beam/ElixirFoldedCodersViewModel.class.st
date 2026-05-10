Class {
	#name : 'ElixirFoldedCodersViewModel',
	#superclass : 'GtStreamingCodersViewModel',
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'accessing' }
ElixirFoldedCodersViewModel >> newCoderViewModelFor: aCoderModel [
	"I produce VMs that start collapsed. Useful for streaming
	 lists of function coders where the user scans the list of
	 signatures first and expands what they want to read."
	^ (super newCoderViewModelFor: aCoderModel)
		expanded: false;
		yourself
]
