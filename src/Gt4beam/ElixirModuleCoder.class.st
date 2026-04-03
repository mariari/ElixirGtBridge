Class {
	#name : 'ElixirModuleCoder',
	#superclass : 'GtCoderModel',
	#traits : 'TGtCoderTrait',
	#classTraits : 'TGtCoderTrait classTrait',
	#instVars : [
		'sourcePath',
		'moduleName',
		'application'
	],
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'accessing' }
ElixirModuleCoder >> application [
	^ application
]

{ #category : 'accessing' }
ElixirModuleCoder >> application: anApp [
	application := anApp
]

{ #category : 'accessing' }
ElixirModuleCoder >> asCoderViewModel [
	^ ElixirModuleCoderViewModel new coder: self
]

{ #category : 'accessing' }
ElixirModuleCoder >> coderName [
	^ moduleName
]

{ #category : 'accessing' }
ElixirModuleCoder >> functionEntries [
	"I return all function entries (def + defp) with line ranges including annotations."
	^ [ application newCommandFactory
		<< ('GtBridge.Analysis.all_functions(', moduleName, ')
  |> then(fn raw ->
    case ', moduleName, '.module_info(:compile)[:source] |> List.to_string() |> File.read() do
      {:ok, source} ->
        lines = String.split(source, "\n")
        raw |> Enum.map(fn f ->
          start = Enum.reduce_while((f.start - 1)..1, f.start, fn i, acc ->
            trimmed = String.trim(Enum.at(lines, i - 1, ""))
            cond do
              trimmed == "" -> {:halt, acc}
              String.starts_with?(trimmed, "@doc") -> {:cont, i}
              String.starts_with?(trimmed, "@spec") -> {:cont, i}
              String.starts_with?(trimmed, "@impl") -> {:cont, i}
              String.starts_with?(trimmed, "#") -> {:cont, i}
              trimmed == ~s(""") -> {:cont, i}
              acc < f.start -> {:cont, i}
              true -> {:halt, acc}
            end
          end)
          Map.put(f, :start, start)
        end)
      _ -> raw
    end
  end)');
		sendAndWait ] on: Error do: [ #() ]
]

{ #category : 'accessing' }
ElixirModuleCoder >> moduleName [
	^ moduleName
]

{ #category : 'accessing' }
ElixirModuleCoder >> moduleName: aString [
	moduleName := aString
]

{ #category : 'actions' }
ElixirModuleCoder >> saveAndCompile: newSource [
	"I write source to disk and recompile the project.
	 Preserves the original file's line ending convention and trailing newline."
	| b64 normalized usesCrlf ending |
	usesCrlf := self sourceCode includesSubstring: String crlf.
	ending := usesCrlf ifTrue: [ String crlf ] ifFalse: [ String lf ].
	normalized := newSource copyReplaceAll: String crlf with: String lf.
	normalized := normalized copyReplaceAll: String cr with: String lf.
	usesCrlf ifTrue: [
		normalized := normalized copyReplaceAll: String lf with: String crlf ].
	(normalized endsWith: ending) ifFalse: [
		normalized := normalized , ending ].
	b64 := ZnBase64Encoder new encode: normalized utf8Encoded.
	^ application newCommandFactory
		<< ('content = Base.decode64!("', b64, '")
File.write!("', sourcePath, '", content)
Mix.Tasks.Format.run(["', sourcePath, '"])
IEx.Helpers.recompile()');
		sendAndWait
]

{ #category : 'actions' }
ElixirModuleCoder >> addFunction: newText [
	"I insert newText before the final end of the module, save, and compile."
	| lines lastEnd newLines |
	lines := self sourceCode lines asOrderedCollection.
	lastEnd := lines size.
	lines size to: 1 by: -1 do: [ :i |
		((lines at: i) trimBoth = 'end') ifTrue: [ lastEnd := i ] ].
	newLines := (lines copyFrom: 1 to: lastEnd - 1) asOrderedCollection.
	newLines add: ''.
	newLines addAll: newText lines.
	newLines addAll: (lines copyFrom: lastEnd to: lines size).
	^ self saveAndCompile: (String lf join: newLines)
]

{ #category : 'actions' }
ElixirModuleCoder >> spliceFunction: newText fromLine: startLine toLine: endLine [
	"I replace lines startLine..endLine in the source with newText, save, and compile."
	| lines newLines |
	lines := self sourceCode lines asOrderedCollection.
	newLines := (lines copyFrom: 1 to: startLine - 1) asOrderedCollection.
	newLines addAll: newText lines.
	newLines addAll: (lines copyFrom: endLine + 1 to: lines size).
	^ self saveAndCompile: (String lf join: newLines)
]

{ #category : 'actions' }
ElixirModuleCoder >> swapFunctions: entryA with: entryB [
	"I swap two function blocks in the source, save, and compile."
	| lines startA endA startB endB blockA blockB newLines |
	startA := entryA attributeAt: #start.
	endA := entryA attributeAt: #end_line.
	startB := entryB attributeAt: #start.
	endB := entryB attributeAt: #end_line.
	lines := self sourceCode lines.
	blockA := lines copyFrom: startA to: endA.
	blockB := lines copyFrom: startB to: endB.
	startA < startB
		ifTrue: [
			newLines := (lines copyFrom: 1 to: startA - 1),
				blockB,
				(lines copyFrom: endA + 1 to: startB - 1),
				blockA,
				(lines copyFrom: endB + 1 to: lines size) ]
		ifFalse: [
			newLines := (lines copyFrom: 1 to: startB - 1),
				blockA,
				(lines copyFrom: endB + 1 to: startA - 1),
				blockB,
				(lines copyFrom: endA + 1 to: lines size) ].
	^ self saveAndCompile: (String cr join: newLines)
]

{ #category : 'accessing' }
ElixirModuleCoder >> sourceCode [
	^ sourcePath asFileReference contents
]

{ #category : 'accessing' }
ElixirModuleCoder >> sourcePath [
	^ sourcePath
]

{ #category : 'accessing' }
ElixirModuleCoder >> sourcePath: aString [
	sourcePath := aString
]
