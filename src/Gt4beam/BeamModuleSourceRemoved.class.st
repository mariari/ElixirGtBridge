"
I announce that a module's source file has been deleted from the GT-side
project tree.  The BEAM image still has the compiled module loaded — only
the source artifact is gone — so derived state needs to flip back to
`unresolved` and any cached source/entries should clear.

Fired by `ElixirModuleCoder>>remove`.
"
Class {
	#name : 'BeamModuleSourceRemoved',
	#superclass : 'BeamModuleAnnouncement',
	#category : 'Gt4beam-Events',
	#package : 'Gt4beam',
	#tag : 'Events'
}
