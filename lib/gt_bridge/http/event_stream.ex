defmodule GtBridge.Http.EventStream do
  @moduledoc """
  I am a Plug that holds a chunked HTTP response open and frames every
  `%GtBridge.Events.ModuleEvent{}` as a Server-Sent Events `data:` line.

  GT side opens `GET /EVENTS` once per session, reads frames as they
  arrive, and feeds them into `BeamEventAnnouncer`.  Together with
  `GtBridge.CodeMonitor`, this is the sole publisher → sole channel
  path for module events.

  ### Wire

  - Endpoint: `GET /EVENTS`
  - Content-Type: `text/event-stream`
  - Frame: `data: <json>\\n\\n`
  """

  import Plug.Conn

  alias EventBroker.Event
  alias GtBridge.Events
  alias GtBridge.Events.ModuleEvent

  def init(opts), do: opts

  def call(conn, _opts) do
    EventBroker.subscribe_me([%Events.AnyModuleEvent{}])

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> send_chunked(200)

    try do
      loop(conn)
    after
      EventBroker.unsubscribe_me([%Events.AnyModuleEvent{}])
    end
  end

  defp loop(conn) do
    receive do
      %Event{body: %ModuleEvent{} = event} ->
        case chunk(conn, "data: #{encode(event)}\n\n") do
          {:ok, conn} -> loop(conn)
          {:error, _closed} -> conn
        end
    end
  end

  defp encode(%ModuleEvent{} = event) do
    Jason.encode!(%{
      kind: event.kind,
      mod: module_name(event.mod),
      source_hash: event.source_hash,
      errors: event.errors
    })
  end

  defp module_name(nil), do: nil

  defp module_name(mod) when is_atom(mod) do
    mod |> to_string() |> String.replace_prefix("Elixir.", "")
  end
end
