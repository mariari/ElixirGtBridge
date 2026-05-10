defmodule GtBridge.Http.SseStream do
  @moduledoc """
  I am the cowboy_loop handler for the `/EVENTS` SSE channel.

  Cowboy's loop handlers are invoked per-message: between events the
  process sits in `:cowboy_loop_h:loop/1` (Cowboy's own code), not in
  user-defined frames.  So bridge module recompiles don't keep this
  module on a long-lived stack and don't kill the streaming process.
  The previous Plug-based implementation died on every-other save
  because of BEAM's two-version code purge cycle.
  """

  alias EventBroker.Event
  alias GtBridge.Events
  alias GtBridge.Events.ModuleEvent

  @type state :: %{optional(:subscribed) => boolean()}

  @spec init(:cowboy_req.req(), term()) ::
          {:cowboy_loop, :cowboy_req.req(), state(), :hibernate}
  def init(req, _state) do
    req = :cowboy_req.set_resp_header("content-type", "text/event-stream", req)
    req = :cowboy_req.set_resp_header("cache-control", "no-cache", req)
    req = :cowboy_req.stream_reply(200, req)
    EventBroker.subscribe_me([%Events.AnyModuleEvent{}])
    {:cowboy_loop, req, %{subscribed: true}, :hibernate}
  end

  @spec info(term(), :cowboy_req.req(), state()) ::
          {:ok, :cowboy_req.req(), state(), :hibernate}
  def info(%Event{body: %ModuleEvent{} = event}, req, state) do
    :cowboy_req.stream_body("data: #{encode(event)}\n\n", :nofin, req)
    {:ok, req, state, :hibernate}
  end

  def info(_other, req, state), do: {:ok, req, state, :hibernate}

  @spec terminate(term(), :cowboy_req.req(), state()) :: :ok
  def terminate(_reason, _req, %{subscribed: true}) do
    EventBroker.unsubscribe_me([%Events.AnyModuleEvent{}])
    :ok
  end

  def terminate(_reason, _req, _state), do: :ok

  @spec encode(ModuleEvent.t()) :: String.t()
  defp encode(%ModuleEvent{} = event) do
    event
    |> Map.from_struct()
    |> Map.update!(:mod, &module_name/1)
    |> Jason.encode!()
  end

  @spec module_name(module() | nil) :: String.t() | nil
  defp module_name(nil), do: nil

  defp module_name(mod) when is_atom(mod) do
    mod |> to_string() |> String.replace_prefix("Elixir.", "")
  end
end
