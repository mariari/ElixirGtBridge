defmodule GtBridge.Events do
  @moduledoc """
  I define the EventBroker filters and the broadcast helper for GtBridge's
  module-event bus.

  Every GtBridge event flows through EventBroker as a
  `%EventBroker.Event{body: %GtBridge.Events.ModuleEvent{}}`. Subscribers
  attach to the filter that matches the slice they care about.

  ### Public API

  - `broadcast/1` — wrap a `%ModuleEvent{}` in an `%EventBroker.Event{}`
    and publish to the broker.

  ### Filters

  - `AnyModuleEvent` — every module event regardless of `:kind`.

  Subscribers that care about a specific kind pattern-match on
  `:kind` themselves rather than going through narrow filters --
  there's no consumer that benefits from the broker doing the
  pre-filtering.
  """

  alias EventBroker.Event
  alias GtBridge.Events.ModuleEvent

  use EventBroker.DefFilter

  deffilter AnyModuleEvent do
    %Event{body: %ModuleEvent{}} -> true
    _ -> false
  end

  @doc """
  I broadcast a `%ModuleEvent{}` to the EventBroker, wrapped in an
  `%EventBroker.Event{}` whose `:source_module` identifies GtBridge.Events
  as the publisher.
  """
  @spec broadcast(ModuleEvent.t()) :: :ok
  def broadcast(%ModuleEvent{} = body) do
    EventBroker.event(%Event{source_module: __MODULE__, body: body})
  end
end
