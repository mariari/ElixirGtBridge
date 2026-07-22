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

  @doc """
  I bring the bridge up.  This is the entry point GT calls once
  connected: I start xref indexing and the framed TCP transport, which
  carries every channel -- evals, completion, bindings, session close,
  and module events -- over one socket.

  The second argument is the legacy client port, unused now that GT runs
  no inbound server; it is kept so the documented call still works.
  """
  def start_listener(port_server, _port_client \\ nil) do
    # Bridge is coming up: begin xref indexing now (deferred from VM boot).
    GtBridge.Xref.start_indexing()
    Tcp.Supervisor.start_listener(port_server)
  end
end
