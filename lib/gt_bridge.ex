defmodule GtBridge do
  use Application

  @moduledoc """
  Documentation for `GtBridge`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> GtBridge.hello()
      :world

  """
  def hello do
    :world
  end

  def start(_type, args) do
    start = GtBridge.Supervisor.start_link(args)
    # Initialize the default views
    GtBridge.View.register(GtBridge.GtViewedObject)
    start
  end

  def start_listener(port \\ 0) do
    DynamicSupervisor.start_child(
      Tcp.Supervisor,
      {Tcp.Listener, [host: {0, 0, 0, 0}, port: port]}
    )
  end
end
