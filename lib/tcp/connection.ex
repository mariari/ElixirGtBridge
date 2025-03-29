defmodule Tcp.Connection do
  @moduledoc """
  I am the TCP Connection for MsgPack messages

  If you are looking for HTTP messages please use someone else.
  """
  require Logger

  use GenServer
  use TypedStruct

  @typedoc """
  Shorthand type for socket.
  """
  @type hostname :: :inet.socket_address() | :inet.hostname()

  @typedoc """
  Shorthand type for port number.
  """
  @type port_number :: :inet.port_number()

  ############################################################
  #                    State                                 #
  ############################################################

  typedstruct do
    @typedoc """
    I am the state of a TCP connection.

    My fields contain information to facilitate the TCP connection with a remote node.

    ### Fields
    - `:socket`         - The socket of the connection.
    """
    field(:socket, port())
    field(:inferior, pid())
  end

  ############################################################
  #                    Genserver Helpers                     #
  ############################################################

  @spec child_spec([any()]) :: Supervisor.child_spec()
  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      restart: :temporary
    }
  end

  @spec start_link([any()]) :: GenServer.on_start()
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  ############################################################
  #                    Genserver Behavior                    #
  ############################################################

  @impl true
  # @doc """
  # I don't do anything useful.
  # """
  def init(args) do
    Process.set_label(__MODULE__)

    Logger.debug("#{inspect(self())} starting tcp connection")
    args = Keyword.validate!(args, [:socket, :existing_inferior_shell])
    state = struct(__MODULE__, Enum.into(args, %{}))

    {:ok, state, {:continue, :announce}}
  end

  @impl true
  def handle_continue(:announce, state) do
    GenServer.cast(self(), {:tcp_out, []})
    {:ok, pid} = DynamicSupervisor.start_child(EvaluationSupervisor, {Eval, []})
    {:noreply, %__MODULE__{state | inferior: pid}}
  end

  @impl true
  # @doc """
  # I send the given bytes over the socket and do not reply.
  # """
  def handle_cast({:tcp_out, message}, state) do
    handle_tcp_out(message, state.socket)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp, _port, msg}, _state) do
    IO.puts("#{Msgpax.unpack(msg)}")
  end

  ############################################################
  #                           Helpers                        #
  ############################################################

  # @doc """
  # I handle a bunch of incoming bytes over the TCP socket.

  # I decode them into a protobuf message and handle them accordingly.
  # """
  @spec handle_tcp_in(any(), String.t()) :: :ok
  def handle_tcp_in(bytes, _local_node_id) do
    Logger.debug("tcp in :: #{inspect(self())} :: #{inspect(bytes)}")

    case decode(bytes) do
      {:ok, message} ->
        Logger.debug("tcp in :: #{inspect(self())} :: #{inspect(message)}")

      # handle_message_in(message, local_node_id)

      {:error, _} ->
        Logger.error("invalid message")
    end
  end

  # @doc """
  # I handle a protobuf message that has to be sent over the wire.

  # I encode the message into byts and push them onto the socket.
  # """
  @spec handle_tcp_out(any(), port()) :: :ok
  defp handle_tcp_out(message, socket) do
    Logger.debug("tcp out :: #{inspect(self())} :: #{inspect(message)}")
    bytes = encode(message)
    :gen_tcp.send(socket, bytes)
  end

  def encode(x), do: x
  def decode(x), do: x
end
