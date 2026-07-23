defmodule Examples.ETcp do
  @moduledoc """
  I am examples for the framed TCP transport.

  Each opens a real `packet: 4` client against a listener on an
  ephemeral port, so the frames exercised here are the frames GT sends.
  """

  use ExExample

  import ExUnit.Assertions

  # A `packet: 4` client connected to a fresh listener, plus a
  # correlate-by-id reader that skips event frames until the reply for a
  # given command arrives -- the discipline GT's reader also follows.
  @spec connect() :: %{socket: :inet.socket(), req: (map() -> map())}
  example connect do
    {:ok, listener} = Tcp.Listener.start_link(host: {0, 0, 0, 0}, port: 0)
    port = Tcp.Listener.port(listener)
    assert is_integer(port) and port > 0

    {:ok, socket} = :gen_tcp.connect(~c"localhost", port, [:binary, packet: 4, active: false])

    recv_reply = fn recv_reply, id ->
      {:ok, raw} = :gen_tcp.recv(socket, 0, 15_000)
      frame = Jason.decode!(raw)
      if frame["id"] == id, do: frame, else: recv_reply.(recv_reply, id)
    end

    req = fn payload ->
      :gen_tcp.send(socket, Jason.encode!(payload))
      recv_reply.(recv_reply, payload.commandId)
    end

    %{socket: socket, req: req}
  end

  # Each example opens its own listener and connection, so none may
  # reuse a cached socket from another.
  def rerun?(_), do: true

  @spec enqueue_scalar() :: map()
  example enqueue_scalar do
    %{req: req} = connect()
    reply = req.(%{type: "ENQUEUE", commandId: "scalar", statements: "1 + 1", bindings: %{}})

    assert reply["id"] == "scalar"
    assert reply["value"] == "2"
    reply
  end

  @spec enqueue_proxy() :: map()
  example enqueue_proxy do
    %{req: req} = connect()
    reply = req.(%{type: "ENQUEUE", commandId: "proxy", statements: "%{a: 1}", bindings: %{}})

    # A complex result comes back as an {exid, exclass} reference, not a
    # materialised copy -- the same encoding the HTTP path uses.
    assert reply["value"] =~ ~s("exclass":"Map")
    reply
  end

  @spec session_bindings_persist() :: map()
  example session_bindings_persist do
    %{req: req} = connect()

    req.(%{
      type: "ENQUEUE",
      commandId: "b1",
      sessionId: "e-tcp",
      statements: "x = 21",
      bindings: %{}
    })

    reply =
      req.(%{
        type: "ENQUEUE",
        commandId: "b2",
        sessionId: "e-tcp",
        statements: "x * 2",
        bindings: %{}
      })

    assert reply["value"] == "42"
    reply
  end

  @spec large_reply_is_framed_whole() :: integer()
  example large_reply_is_framed_whole do
    %{req: req} = connect()

    reply =
      req.(%{
        type: "ENQUEUE",
        commandId: "big",
        statements: ~s|String.duplicate("ab", 200_000)|,
        bindings: %{}
      })

    bytes = byte_size(reply["value"])
    # 400_000 chars plus the two JSON quotes: one whole frame, not a
    # truncated read.
    assert bytes == 400_002
    bytes
  end
end
