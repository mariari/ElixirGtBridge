defmodule GtBridge.Events.ModuleEvent do
  @moduledoc """
  I am the body of an EventBroker event announcing a change to a BEAM module.

  My `:kind` discriminates the change:

  - `:recompiled` — module successfully reloaded; subscribers should refresh
    their derived state.
  - `:compile_failed` — a save attempt did not produce a new module; subscribers
    that surface compile errors react, no cache invalidation should fire.
  - `:source_written` — disk has new bytes (regardless of compile outcome);
    subscribers re-baseline against `:source` + `:functions`.
  - `:source_removed` — module's source file was deleted; subscribers should
    drop cached entries for that module.
  """

  use TypedStruct

  @type kind :: :recompiled | :compile_failed | :source_written | :source_removed

  typedstruct do
    field(:kind, kind(), enforce: true)
    field(:mod, module() | nil, default: nil)
    field(:source_hash, integer() | nil, default: nil)
    field(:source, String.t() | nil, default: nil)
    field(:functions, list(map()) | nil, default: nil)
    field(:errors, list() | nil, default: nil)
  end
end
