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
  I bring the bridge up on `port`.  This is the entry point GT calls
  once connected: I start xref indexing and the framed TCP transport,
  which carries every channel -- evals, completion, bindings, session
  close, and module events -- over one full-duplex socket.  There is no
  client port: GT reads replies and events back on the socket it opened.
  """
  def start_listener(port) do
    # Bridge is coming up: begin xref indexing now (deferred from VM boot).
    GtBridge.Xref.start_indexing()
    Tcp.Supervisor.start_listener(port)
  end
end
