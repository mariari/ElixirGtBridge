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
  I bring the bridge's transports up.  This is the transport-neutral
  entry point GT calls once connected: I start xref indexing, the framed
  TCP transport (the default, one port above HTTP), and the HTTP server
  that still carries the channels not yet moved over.
  """
  def start_listener(port_server, port_client) do
    # Bridge is coming up: begin xref indexing now (deferred from VM boot).
    GtBridge.Xref.start_indexing()
    Tcp.Supervisor.start_listener(port_server + 1)
    GtBridge.Http.Supervisor.start_listener(port_server, port_client)
  end
end
