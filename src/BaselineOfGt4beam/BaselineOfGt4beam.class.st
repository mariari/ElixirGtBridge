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
			"used to ensure that elixir snippets are loaded correctly"
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
