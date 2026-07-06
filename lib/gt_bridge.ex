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
    # Blocks startup; defer it.
    Task.start(&GtBridge.View.register_all/0)
    result
  end

  def start_listener(port \\ 0) do
    # Bridge is coming up: begin xref indexing now (deferred from VM boot).
    GtBridge.Xref.start_indexing()

    DynamicSupervisor.start_child(
      Tcp.Supervisor,
      {Tcp.Listener, [host: {0, 0, 0, 0}, port: port]}
    )
  end
end
