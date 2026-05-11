Extension { #name : 'GtSpotterStart' }

{ #category : '*Gt4beam' }
GtSpotterStart >> gtSearchBeamApplicationsFor: aSearch [
	<gtSearch>
	^ (ElixirSystemAnalysis
		beamSearchFor: aSearch
		queryFn: 'search_apps'
		send: [ :appName :app |
			(ElixirSystemAnalysis onApplication: app) applications
				detect: [ :a | a name symbol asString = appName ]
				ifNone: [ appName ] ])
		title: 'BEAM applications';
		priority: 81
]

{ #category : '*Gt4beam' }
GtSpotterStart >> gtSearchBeamModulesFor: aSearch [
	<gtSearch>
	^ (ElixirSystemAnalysis
		beamSearchFor: aSearch
		queryFn: 'search_modules'
		send: [ :modName :app |
			app evaluateAndWait:
				'GtBridge.Documentation.for_module(', modName, ')' ])
		itemName: [ :modName | modName withoutPrefix: 'Elixir.' ];
		title: 'BEAM modules';
		priority: 80
]
