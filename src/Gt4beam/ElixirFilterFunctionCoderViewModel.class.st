Class {
	#name : 'ElixirFilterFunctionCoderViewModel',
	#superclass : 'ElixirFunctionCoderViewModel',
	#category : 'Gt4beam-Coder',
	#package : 'Gt4beam',
	#tag : 'Coder'
}

{ #category : 'accessing' }
ElixirFilterFunctionCoderViewModel >> headerElementClass [
	"GT framework reads this on the view model and adds the class's
	 instance as the first child of the collapsed/expanded content
	 elements (see GtSourceCoderContentElement>>onTextualCoderViewModelChanged).
	 wantsHeader on GtExpandableCoderViewModel returns true automatically
	 when this is non-nil."
	^ ElixirFunctionCoderHeaderElement
]
