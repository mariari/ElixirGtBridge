defmodule GtBridge.Events.ModuleEvent do
  @moduledoc """
  I am the body of an EventBroker event announcing a change to a BEAM module.

  `:kind` is one of `:recompiled`, `:compile_failed`, `:source_written`.
  Directly-saved modules carry `:source` + `:functions` inline; sibling
  cascades arrive bare.
  """

  use TypedStruct

  typedstruct do
    field(:kind, :recompiled | :compile_failed | :source_written, enforce: true)
    field(:mod, module() | nil, default: nil)
    field(:source_hash, integer() | nil, default: nil)
    field(:source, String.t() | nil, default: nil)
    field(:functions, list(map()) | nil, default: nil)
    field(:errors, list() | nil, default: nil)
  end
end
