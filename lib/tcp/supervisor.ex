defmodule Tcp.Supervisor do
  @moduledoc """
  I am a TCP Supervisor, I supervise TCP Listeners and Connections

  There are no default TCP Listeners by default, instead I expect you
  to instruct me to spawn up listeners
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  # We don't have any children by default wait until one spawns it up
  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 1_000_000, max_seconds: 1)
  end
end
