Class {
	#name : 'BaselineOfGt4beam',
	#superclass : 'BaselineOf',
	#category : 'BaselineOfGt4beam',
	#package : 'BaselineOfGt4beam'
}

{ #category : 'loading' }
BaselineOfGt4beam class >> loadLepiter [
	IceRepository registry  
		detect: [ :aRepository |
			aRepository name = 'ElixirGtBridge' ]
		ifFound: [ :aRepository | 
			| defaultDatabase currentProperties |
			defaultDatabase := LeDatabasesRegistry defaultLogicalDatabase.
			currentProperties := defaultDatabase properties.
			currentProperties addRegisteredDirectory: aRepository repositoryDirectory / 'lepiter'.
			"Reset the cached snippet type mapping so LeJsonV4
			 discovers LeElixirSnippet, then reload all pages."
			LeJsonV4 cleanUp.
			LeLogicalDatabase allInstancesDo: #fullReload ]
		ifNone: [
			self inform: 'Repository not found.' ]
]

{ #category : 'baseline' }
BaselineOfGt4beam >> baseline: spec [
	<baseline>
		^ spec for: #common do: [
			spec package: 'Gt4beam'
		]
]
