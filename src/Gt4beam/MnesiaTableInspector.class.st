Class {
	#name : 'MnesiaTableInspector',
	#superclass : 'Object',
	#instVars : [
		'tableName',
		'application'
	],
	#category : 'Gt4beam-Analysis',
	#package : 'Gt4beam',
	#tag : 'Analysis'
}

{ #category : 'accessing' }
MnesiaTableInspector >> application: anApp [
	application := anApp
]

{ #category : 'private' }
MnesiaTableInspector >> eval: aString [
	^ application newCommandFactory << aString; sendAndWait
]

{ #category : 'gt-views' }
MnesiaTableInspector >> gtRecordsFor: aView [
	<gtView>
	<gtBeamView>
	^ aView columnedList
		title: 'Records';
		priority: 10;
		items: [ (self eval:
			'GtBridge.Mnesia.records(', self quotedTableAtom, ')') asList ];
		column: 'Key' text: [ :row |
			row asList first itemAt: 1 ] weight: 2;
		column: 'Record' text: [ :row |
			', ' join: (row asList allButFirst collect: [ :pair |
				(pair itemAt: 0), '=', (pair itemAt: 1) ]) ];
		send: [ :row |
			| dict |
			dict := Dictionary new.
			row asList do: [ :pair | dict at: (pair itemAt: 0) put: (pair itemAt: 1) ].
			dict ]
]

{ #category : 'gt-views' }
MnesiaTableInspector >> gtSchemaFor: aView [
	<gtView>
	<gtBeamView>
	^ aView columnedList
		title: 'Schema';
		priority: 5;
		items: [ | info |
			info := self eval:
				'GtBridge.Mnesia.schema(', self quotedTableAtom, ')'.
			{
			{ 'Table'. tableName }.
			{ 'Type'. (info attributeAt: #type) asString }.
			{ 'Size'. (info attributeAt: #size) asString }.
			{ 'Memory (words)'. (info attributeAt: #memory) asString }.
			{ 'Storage'. (info attributeAt: #storage) asString }.
			{ 'Record name'. (info attributeAt: #record_name) asString }.
			{ 'Attributes'. info attributeAt: #attributes }.
			{ 'Indexes'. info attributeAt: #indexes }.
			{ 'Access mode'. (info attributeAt: #access_mode) asString }.
			{ 'Load order'. (info attributeAt: #load_order) asString } } ];
		column: 'Property' text: #first;
		column: 'Value' text: #second
]

{ #category : 'printing' }
MnesiaTableInspector >> printOn: aStream [
	aStream nextPutAll: 'MnesiaTable('; nextPutAll: tableName; nextPut: $)
]

{ #category : 'private' }
MnesiaTableInspector >> quotedTableAtom [
	^ ':"', tableName, '"'
]

{ #category : 'accessing' }
MnesiaTableInspector >> tableName: aString [
	tableName := aString
]
