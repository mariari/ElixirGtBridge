defmodule GtBridge.Events.ModuleEvent do
  @moduledoc """
  I am the body of an EventBroker event announcing a change to a BEAM module.

  My `:kind` discriminates the change:

  - `:recompiled` — module successfully reloaded; subscribers should refresh
    their derived state.
  - `:compile_failed` — a save attempt did not produce a new module; subscribers
    that surface compile errors react, no cache invalidation should fire.
  """

  use TypedStruct

  typedstruct do
    field(:kind, :recompiled | :compile_failed, enforce: true)
    field(:mod, module() | nil, default: nil)
    field(:source_hash, integer() | nil, default: nil)
    field(:errors, list() | nil, default: nil)
  end
end
