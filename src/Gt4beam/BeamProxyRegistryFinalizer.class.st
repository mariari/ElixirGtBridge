"
I am the finalizer {{gtClass:BeamProxyObject}} registers.  Instead of
sending a removal of my own, I hand my id to
{{gtClass:BeamRegistryReaper}}, which batches them.
"
Class {
	#name : 'BeamProxyRegistryFinalizer',
	#superclass : 'LanguageLinkRegistryFinalizer',
	#category : 'Gt4beam-Global',
	#package : 'Gt4beam',
	#tag : 'Global'
}

{ #category : 'finalization' }
BeamProxyRegistryFinalizer >> finalize [
	"Hand the id to the reaper; one send per proxy stalls the bridge."
	self application isRunning ifFalse: [ ^ self ].
	BeamRegistryReaper removeId: self proxyObjectId handler: self executionHandler
]
