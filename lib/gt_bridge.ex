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
    result = GtBridge.Supervisor.start_link(args)
    GtBridge.View.register_all()
    result
  end

  def start_listener(port \\ 0) do
    DynamicSupervisor.start_child(
      Tcp.Supervisor,
      {Tcp.Listener, [host: {0, 0, 0, 0}, port: port]}
    )
  end
end
