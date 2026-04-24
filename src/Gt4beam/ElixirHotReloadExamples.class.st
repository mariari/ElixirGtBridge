Class {
	#name : 'ElixirHotReloadExamples',
	#superclass : 'Object',
	#category : 'Gt4beam',
	#package : 'Gt4beam'
}

{ #category : 'examples - save' }
ElixirHotReloadExamples >> doubleSavePreservesSource [
	"I save a function twice and verify the module source
	 isn't corrupted — no duplicated ends or lost code."
	<gtExample>
	| modCoder funcCoder original afterDouble |
	modCoder := self moduleCoder.
	original := modCoder sourceCode.
	funcCoder := self functionCoder.
	funcCoder sourceCode: (GtCoderExplicitStringSource new
		source: '  def hello, do: :first_save').
	[ funcCoder saveFunction.
	  funcCoder sourceCode: (GtCoderExplicitStringSource new
		source: '  def hello, do: :second_save').
	  funcCoder saveFunction.
	  afterDouble := modCoder sourceCode.
	  self assert: (afterDouble lines select: [ :l | l trimBoth = 'end' ]) size
	       equals: (original lines select: [ :l | l trimBoth = 'end' ]) size.
	  self assert: (modCoder application evaluateAndWait: 'HotReloadTest.hello()') symbol
	       equals: #second_save ]
		ensure: [ modCoder saveAndCompile: original ].
	^ modCoder
]

{ #category : 'examples - setup' }
ElixirHotReloadExamples >> functionCoder [
	"I return an ElixirFunctionCoder for hello/0 from the module coder."
	<gtExample>
	| modCoder entries funcCoder |
	modCoder := self moduleCoder.
	entries := modCoder functionEntries asList.
	self assert: entries isNotEmpty.
	funcCoder := ElixirFunctionCoder new.
	funcCoder initializeFromEntry: entries first moduleCoder: modCoder.
	self assert: funcCoder functionName equals: 'hello'.
	self assert: funcCoder arity equals: 0.
	^ funcCoder
]

{ #category : 'examples - setup' }
ElixirHotReloadExamples >> moduleCoder [
	"I return an ElixirModuleCoder wired to the HotReloadTest fixture dep."
	<gtExample>
	| app coder path |
	app := BeamLinkApplication uniqueInstance.
	path := app evaluateAndWait: 'GtBridge.Resolve.source_file(HotReloadTest)'.
	self assert: path isNotNil description: 'HotReloadTest must be loaded'.
	coder := ElixirModuleCoder new.
	coder application: app.
	coder moduleName: 'HotReloadTest'.
	coder sourcePath: path.
	self assert: coder hasFunctions.
	^ coder
]

{ #category : 'examples - save' }
ElixirHotReloadExamples >> saveFunctionEditsBody [
	"I edit hello's return value via saveFunction and verify
	 the change takes effect on the BEAM side."
	<gtExample>
	| modCoder funcCoder original result |
	modCoder := self moduleCoder.
	original := modCoder sourceCode.
	funcCoder := self functionCoder.
	funcCoder sourceCode: (GtCoderExplicitStringSource new
		source: '  def hello, do: :edited').
	[ funcCoder saveFunction.
	  result := modCoder application evaluateAndWait: 'HotReloadTest.hello()'.
	  self assert: result symbol equals: #edited ]
		ensure: [ modCoder saveAndCompile: original ].
	^ funcCoder
]
