defmodule GtBridge.Eval.Error do
  @moduledoc """
  I reprsent an error in evaluation

  We are a custom type so the GT side can easily create views of me!
  """
  use TypedStruct

  typedstruct do
    field(:trace, Exception.stacktrace())
    field(:error, any())
    field(:kind, Exception.non_error_kind())
  end

  # Very course first attempt, please improve me!
  @spec dump_error(t()) :: String.t()
  def dump_error(%__MODULE__{trace: trace, error: error, kind: kind}) do
    {blamed, trace} = Exception.blame(kind, error, trace)

    Exception.format_banner(kind, blamed, trace) <>
      "\n" <>
      Exception.format_stacktrace(trace)
  end
end
