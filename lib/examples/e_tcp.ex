defmodule Examples.ETcp do
  import ExUnit.Assertions

  @spec start_listener() :: :ignore | {:error, any()} | {:ok, pid()} | {:ok, pid(), any()}
  def start_listener(port \\ 0) do
    GtBridge.start_listener(port)
  end

  @spec start_tcp_connection(integer()) :: {:ok, port()}
  def start_tcp_connection(port \\ 0) do
    {:ok, pid} = start_listener(port)
    real_port = Tcp.Listener.port(pid)
    assert real_port == port || port == 0
    socket_opts = [:binary, active: false, exit_on_close: true, reuseaddr: true]
    {:ok, _exposed_port} = :gen_tcp.connect({0, 0, 0, 0}, real_port, socket_opts)
  end
end
