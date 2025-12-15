defmodule EvaluationSupervisor do
  @moduledoc """
  I supervise children that evaluate arbitrary Elixir code (Similar to IEx).

  In particular I expect the host platform to spawn up multiple
  instances of children, so I am a DynamicSupervisor.

  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  # We don't have any children by default wait until one spawns it up
  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
