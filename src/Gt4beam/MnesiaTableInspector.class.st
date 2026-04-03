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
MnesiaTableInspector >> application [
	^ application
]

{ #category : 'accessing' }
MnesiaTableInspector >> application: anApp [
	application := anApp
]

{ #category : 'gt-views' }
MnesiaTableInspector >> gtRecordsFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Records';
		priority: 10;
		items: [ (self eval:
			'attrs = :mnesia.table_info(:', tableName, ', :attributes)
			:mnesia.dirty_all_keys(:', tableName, ')
			|> Enum.take(500)
			|> Enum.flat_map(fn key ->
				:mnesia.dirty_read(:', tableName, ', key)
				|> Enum.map(fn rec ->
					values = rec |> Tuple.to_list() |> tl()
					Enum.zip(attrs, values)
					|> Enum.map(fn {a, v} -> {Atom.to_string(a), inspect(v)} end)
				end)
			end)') asList ];
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
	^ aView columnedList
		title: 'Schema';
		priority: 5;
		items: [ | info |
			info := self eval:
				't = :', tableName, '
				%{type: :mnesia.table_info(t, :type),
				  size: :mnesia.table_info(t, :size),
				  memory: :mnesia.table_info(t, :memory),
				  storage: :mnesia.table_info(t, :storage_type),
				  record_name: :mnesia.table_info(t, :record_name),
				  attributes: :mnesia.table_info(t, :attributes) |> Enum.map(fn a -> Atom.to_string(a) end) |> Enum.join(", "),
				  indexes: :mnesia.table_info(t, :index) |> inspect(),
				  access_mode: :mnesia.table_info(t, :access_mode),
				  load_order: :mnesia.table_info(t, :load_order)}'.
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

{ #category : 'accessing' }
MnesiaTableInspector >> tableName [
	^ tableName
]

{ #category : 'accessing' }
MnesiaTableInspector >> tableName: aString [
	tableName := aString
]

{ #category : 'private' }
MnesiaTableInspector >> eval: aString [
	^ application newCommandFactory << aString; sendAndWait
]
