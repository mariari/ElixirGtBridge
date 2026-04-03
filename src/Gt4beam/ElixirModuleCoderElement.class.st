Class {
	#name : 'ElixirModuleCoderElement',
	#superclass : 'BlElement',
	#traits : 'TBrLayoutResizable',
	#classTraits : 'TBrLayoutResizable classTrait',
	#instVars : [
		'coderViewModel'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'building' }
ElixirModuleCoderElement >> buildFunctionsTab [
	^ BrTab new
		aptitude: BrGlamorousTabAptitude new;
		label: 'Functions';
		stencil: [
			| list entries sourceLines |
			entries := self coder functionEntries asList.
			sourceLines := self coder sourceCode lines.
			list := BrSimpleList new matchParent.
			list stencil: [ :entry |
				| name arity startLine endLine funcSource editor container toolbar idx |
				name := entry attributeAt: #name.
				arity := entry attributeAt: #arity.
				startLine := entry attributeAt: #start.
				endLine := entry attributeAt: #end_line.
				funcSource := String cr join:
					(sourceLines copyFrom: startLine to: (endLine min: sourceLines size)).
				editor := BrEditor new
					aptitude: BrGlamorousCodeEditorAptitude new;
					text: funcSource asRopedText;
					hMatchParent;
					vFitContentLimited;
					constraintsDo: [ :c | c maxHeight: 300 ].
				[ editor editor styler: ElixirParser gtStyler ] on: Error do: [ "skip styling" ].
				container := BrVerticalPane new
					hMatchParent; vFitContent;
					padding: (BlInsets all: 4);
					border: (BlBorder paint: (Color gray alpha: 0.2) width: 1);
					margin: (BlInsets top: 2 bottom: 2).
				toolbar := BrHorizontalPane new
					hMatchParent; vFitContent.
				toolbar addChild: (BrLabel new
					aptitude: (BrGlamorousLabelAptitude new glamorousCodeFont; bold);
					text: (entry attributeAt: #sig)).
				toolbar addChild: (BrFrame new hMatchParent; vFitContent).
				arity = 0 ifTrue: [
					toolbar addChild: (BrButton new
						aptitude: BrGlamorousButtonWithIconAptitude;
						icon: BrGlamorousVectorIcons play; beSmallSize;
						label: 'Run';
						action: [ :btn |
							btn phlow spawnObject:
								(self coder application newCommandFactory
									<< (self coder moduleName, '.', name, '()');
									sendAndWait) ]) ].
				toolbar addChild: (BrButton new
					aptitude: BrGlamorousButtonWithIconAptitude;
					icon: BrGlamorousVectorIcons accept; beSmallSize;
					label: 'Save';
					action: [ :btn |
						btn phlow spawnObject:
							(self coder spliceFunction: editor text asString
								fromLine: startLine toLine: endLine) ]).
				idx := entries indexOf: entry.
				idx > 1 ifTrue: [
					toolbar addChild: (BrButton new
						aptitude: BrGlamorousButtonWithIconAptitude;
						icon: BrGlamorousVectorIcons up; beSmallSize;
						label: 'Move up';
						action: [ :btn |
							self coder swapFunctions: (entries at: idx - 1) with: entry.
							self buildUI ]) ].
				idx < entries size ifTrue: [
					toolbar addChild: (BrButton new
						aptitude: BrGlamorousButtonWithIconAptitude;
						icon: BrGlamorousVectorIcons down; beSmallSize;
						label: 'Move down';
						action: [ :btn |
							self coder swapFunctions: entry with: (entries at: idx + 1).
							self buildUI ]) ].
				container addChild: toolbar.
				container addChild: editor.
				container ].
			list items: entries.
			list ]
]

{ #category : 'building' }
ElixirModuleCoderElement >> buildHeader [
	| container nameLabel |
	container := BrHorizontalPane new
		hMatchParent;
		vFitContent;
		alignCenterLeft;
		padding: (BlInsets top: 5 left: 6 bottom: 5 right: 6).
	nameLabel := BrLabel new
		aptitude: (BrGlamorousLabelAptitude new glamorousCodeFont; bold; fontSize: 16);
		text: self coder moduleName.
	container addChild: nameLabel.
	container addChild: (BrFrame new vFitContent; hMatchParent).
	container addChild: (BrButton new
		aptitude: BrGlamorousButtonWithIconAptitude;
		icon: BrGlamorousVectorIcons add; beSmallSize;
		label: 'Add function';
		action: [ :btn |
			| editor popup |
			editor := BrEditor new
				aptitude: BrGlamorousCodeEditorAptitude new;
				text: ('def new_function do' , String cr , '  :ok' , String cr , 'end') asRopedText;
				hExact: 400; vExact: 150.
			editor editor styler: ElixirParser gtStyler.
			popup := BrVerticalPane new
				vFitContent; hFitContent;
				padding: (BlInsets all: 8);
				background: Color white;
				addAptitude: BrGlamorousFocusableShadowAptitude new;
				addChild: editor;
				addChild: (BrButton new
					aptitude: BrGlamorousButtonWithLabelAptitude new;
					label: 'Add & compile';
					action: [ :addBtn |
						self coder addFunction: editor text asString.
						popup removeFromParent.
						self buildUI ]).
			btn phlow spawnObject: popup ]).
	container addChild: (BrButton new
		aptitude: BrGlamorousButtonWithIconAptitude;
		icon: BrGlamorousVectorIcons accept; beSmallSize;
		label: 'Save & compile';
		action: [ :btn |
			btn phlow spawnObject:
				(self coder saveAndCompile: self coder sourceCode) ]).
	^ container
]

{ #category : 'building' }
ElixirModuleCoderElement >> buildSourceTab [
	^ BrTab new
		aptitude: BrGlamorousTabAptitude new;
		label: 'Source';
		stencil: [
			| container editor |
			editor := BrEditor new
				aptitude: BrGlamorousCodeEditorAptitude new;
				text: self coder sourceCode asRopedText;
				matchParent.
			[ editor editor styler: ElixirParser gtStyler ] on: Error do: [ ].
			container := BrVerticalPane new matchParent.
			container addChild: (BrHorizontalPane new
				hMatchParent; vFitContent;
				padding: (BlInsets all: 3);
				addChild: (BrFrame new hMatchParent; vFitContent);
				addChild: (BrButton new
					aptitude: BrGlamorousButtonWithIconAptitude;
					icon: BrGlamorousVectorIcons accept; beSmallSize;
					label: 'Save & compile';
					action: [ :btn |
						btn phlow spawnObject:
							(self coder saveAndCompile: editor text asString) ])).
			container addChild: editor.
			container ]
]

{ #category : 'building' }
ElixirModuleCoderElement >> buildExampleMapTab [
	"I return an Examples tab if this module uses ExExample, or nil."
	| hasExamples |
	hasExamples := [ self coder application newCommandFactory
		<< ('function_exported?(', self coder moduleName, ', :__examples__, 0)');
		sendAndWait ] on: Error do: [ false ].
	hasExamples ifFalse: [ ^ nil ].
	^ BrTab new
		aptitude: BrGlamorousTabAptitude new;
		label: 'Examples';
		stencil: [
			| mondrian data edges nodes modName app |
			app := self coder application.
			modName := self coder moduleName.
			data := app newCommandFactory
				<< ('mod = ', modName, '
				examples = mod.__examples__()
				example_names = Keyword.keys(examples) |> MapSet.new()
				Enum.map(examples, fn {name, calls} ->
					deps = calls
					|> Enum.filter(fn {{m, _}, _} -> m == mod end)
					|> Enum.map(fn {{_, fun}, _} -> fun end)
					|> Enum.filter(fn fun -> fun in example_names end)
					|> Enum.uniq()
					{Atom.to_string(name), Enum.map(deps, fn d -> Atom.to_string(d) end)}
				end)');
				sendAndWait.
			edges := OrderedCollection new.
			data asList do: [ :pair |
				| from tos |
				from := pair itemAt: 0.
				tos := (pair itemAt: 1) asList.
				tos do: [ :to | edges add: from -> to ] ].
			nodes := data asList collect: [ :pair | pair itemAt: 0 ].
			mondrian := GtMondrian new.
			mondrian nodes
				stencil: [ :name |
					BeamMondrianHelpers
						nodeLabeled: name
						color: (Color fromHexString: '#e6f5ec')
						onClick: [ :evt |
							evt target phlow spawnObject:
								(app newCommandFactory << (modName, '.', name, '()'); sendAndWait) ] ];
				with: nodes.
			mondrian edges stencil: [ BeamMondrianHelpers edgeStencil ];
				connectToAll: [ :name |
					(edges select: [ :e | e key = name ]) collect: #value ].
			mondrian layout horizontalTree.
			mondrian root matchParent ]
]

{ #category : 'building' }
ElixirModuleCoderElement >> buildTabs [
	| tabGroup |
	tabGroup := BrTabGroup new aptitude: BrGlamorousTabGroupAptitude new.
	tabGroup constraintsDo: [ :c |
		c horizontal matchParent.
		c vertical matchParent ].
	tabGroup addTab: self buildFunctionsTab.
	tabGroup addTab: self buildSourceTab.
	self buildExampleMapTab ifNotNil: [ :tab | tabGroup addTab: tab ].
	^ tabGroup
]

{ #category : 'building' }
ElixirModuleCoderElement >> buildUI [
	self removeChildren.
	self addChild: self buildHeader.
	self addChild: self buildTabs
]

{ #category : 'accessing' }
ElixirModuleCoderElement >> coder [
	^ coderViewModel coder
]

{ #category : 'accessing' }
ElixirModuleCoderElement >> coderViewModel: aCoderViewModel [
	coderViewModel := aCoderViewModel.
	self buildUI
]

{ #category : 'initialization' }
ElixirModuleCoderElement >> initialize [
	super initialize.
	self
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical matchParent ]
]
