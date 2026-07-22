defmodule Tcp.Connection do
  @moduledoc """
  I serve one GT connection over a length-framed socket.

  Requests and module events share my mailbox, which is the point: a
  reply is a frame carrying the `id` GT sent, an event is a frame with
  none, and GT tells them apart on arrival.  One socket carries both
  directions, so there is no second connection for GT to lose.

  I evaluate in a spawned task rather than inline: an eval may take as
  long as user code takes, and events queued behind a `Process.sleep/1`
  would arrive late.  Replies carry their `id`, so they may return in
  any order.
  """
  require Logger

  use GenServer
  use TypedStruct

  alias EventBroker.Event
  alias GtBridge.Events
  alias GtBridge.Events.ModuleEvent

  ############################################################
  #                    State                                 #
  ############################################################

  typedstruct do
    @typedoc """
    I am the state of a TCP connection.

    ### Fields
    - `:socket` - The socket of the connection.
    """
    field(:socket, port())
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
  def init(args) do
    Process.set_label(__MODULE__)
    args = Keyword.validate!(args, [:socket])
    EventBroker.subscribe_me([%Events.AnyModuleEvent{}])
    {:ok, struct(__MODULE__, Enum.into(args, %{}))}
  end

  @impl true
  def handle_info({:tcp, _socket, frame}, state) do
    case Jason.decode(frame) do
      {:ok, request} -> serve(request, state.socket)
      {:error, _} -> :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_closed, _port}, state), do: {:stop, :normal, state}

  @impl true
  def handle_info({:tcp_error, _port, _reason}, state), do: {:stop, :normal, state}

  @impl true
  def handle_info(%Event{body: %ModuleEvent{} = event}, state) do
    send_frame(state.socket, encode_event(event))
    {:noreply, state}
  end

  @impl true
  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, _state) do
    EventBroker.unsubscribe_me([%Events.AnyModuleEvent{}])
    :ok
  end

  ############################################################
  #                           Helpers                        #
  ############################################################

  defp serve(request, socket) do
    Task.start(fn ->
      case Tcp.Dispatch.reply_to(request) do
        :no_reply -> :ok
        reply -> send_frame(socket, reply)
      end
    end)
  end

  defp send_frame(socket, message), do: :gen_tcp.send(socket, Jason.encode!(message))

  # Same shape `GtBridge.Http.SseStream` puts on the wire, so GT reads
  # an event identically whichever transport delivered it.
  defp encode_event(%ModuleEvent{} = event) do
    event
    |> Map.from_struct()
    |> Map.update!(:mod, &module_name/1)
  end

  defp module_name(nil), do: nil

  defp module_name(mod) when is_atom(mod),
    do: mod |> to_string() |> String.replace_prefix("Elixir.", "")
end
