Extension { #name : 'GtSmaCCParserStyler' }

{ #category : '*Gt4beam' }
GtSmaCCParserStyler class >> elixirStyler: aParserClass [
	<smaccStyler: #ElixirParser priority: 50>
	| specialNodes |
	specialNodes := BeamStylerUtilities keywords
			collect: [ :aToken | 
				GtSmaCCTokenValueStylerRule
					tokenName: aToken
					styleBlock: [ :styler | 
						styler
							bold;
							foreground: Color purple ] ].
	^ (self forParser: aParserClass)
		stylerRules: {GtSmaCCNodeStylerRule
					nodeClassName: #ElixirTrueNode
					styleBlock: [ :styler :node :text | (text from: node startPosition to: node stopPosition) foreground: Color orange ].
				GtSmaCCNodeStylerRule
					nodeClassName: #ElixirNilNode
					styleBlock: [ :styler :node :text | (text from: node startPosition to: node stopPosition) foreground: Color orange ].
				GtSmaCCNodeStylerRule
					nodeClassName: #ElixirFalseNode
					styleBlock: [ :styler :node :text | (text from: node startPosition to: node stopPosition) foreground: Color orange ].
				GtSmaCCCommentStylerRule
					styleBlock: [ :styler | styler foreground: Color lightGray ].
				GtSmaCCNodeStylerRule
					nodeClassName: #ElixirNumberNode
					styleBlock: [ :styler | styler foreground: Color blue ].
				GtSmaCCNodeStylerRule
					nodeClassName: #ElixirBinStringNode
					styleBlock: [ :styler | styler foreground: Color blue ].
				GtSmaCCNodeStylerRule
					nodeClassName: #ElixirListNode
					styleBlock: [ :styler :node :text | 
						BeamStylerUtilities
							colorAndHighlightParenthesesLeft: node startPosition
							right: node stopPosition
							atNestingLevel: node listDepth
							inText: text
							leftLength: 0 ].
				GtSmaCCNodeStylerRule
					nodeClassName: #ElixirMapNode
					styleBlock: [ :styler :node :text | 
						BeamStylerUtilities
							colorAndHighlightParenthesesLeft: node startPosition
							right: node stopPosition
							atNestingLevel: node listDepth
							inText: text
							leftLength: 1
									+ (node struct ifNil: [ 0 ] ifNotNil: [ :aStruct | aStruct source size ]) ].
				GtSmaCCNodeStylerRule
					nodeClassName: #ElixirAtomNode
					styleBlock: [ :styler | styler italic ].
				GtSmaCCNodeStylerRule
					nodeClassName: #ElixirBlockExprNode
					styleBlock: [ :styler :node :text | 
						(text
							from: node call expressions first identifier startPosition
							to: node call expressions first identifier stopPosition) italic bold ].
				GtSmaCCNodeStylerRule
					nodeClassName: #ElixirDotAliasNode
					styleBlock: [ :styler | styler bold ].
				GtSmaCCNodeStylerRule
					nodeClassName: #ElixirDoBlockNode
					styleBlock: [ :styler :node :text | 
						BeamStylerUtilities
							highlightParenthesesLeft: node startPosition
							right: node stopPosition
							inText: text ].
				GtSmaCCNodeVariableStylerRule
					nodeClassName: #SmaCCErrorNode
					variableNames: #(dismissedTokens errorToken)
					styleBlock: [ :styler | styler foreground: Color red ]} , specialNodes
]
