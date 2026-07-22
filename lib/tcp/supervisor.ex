defmodule Tcp.Supervisor do
  @moduledoc """
  I supervise the framed-transport `Tcp.Listener` and its `Tcp.Connection`
  children.  I start empty; `start_listener/1` brings a listener up.
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc "I bring up a framed-transport listener on `port`."
  def start_listener(port) do
    DynamicSupervisor.start_child(__MODULE__, {Tcp.Listener, host: {0, 0, 0, 0}, port: port})
  end

  # We don't have any children by default wait until one spawns it up
  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 1_000_000, max_seconds: 1)
  end
end
