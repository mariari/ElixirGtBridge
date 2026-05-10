defmodule Examples.ECodeMonitor do
  @moduledoc """
  I am examples for `GtBridge.CodeMonitor`, the sole publisher of
  `%ModuleEvent{kind: :recompiled}` on the bridge's EventBroker bus.

  Each example subscribes to `Events.AnyModuleEvent` directly so it
  observes what the monitor publishes — no GT-side machinery required.
  """

  use ExExample

  import ExUnit.Assertions

  alias EventBroker.Event
  alias GtBridge.Events
  alias GtBridge.Events.ModuleEvent

  def rerun?(_), do: true

  @doc "I subscribe and drain pending events for the duration of an example."
  @spec subscribe_and_drain(non_neg_integer()) :: [{atom(), module() | nil}]
  example subscribe_and_drain(timeout_ms \\ 400) do
    EventBroker.subscribe_me([%Events.AnyModuleEvent{}])

    drained =
      for _ <- 1..50 do
        receive do
          %Event{body: %ModuleEvent{} = ev} -> {ev.kind, ev.mod}
        after
          timeout_ms -> :empty
        end
      end
      |> Enum.reject(&(&1 == :empty))

    EventBroker.unsubscribe_me([%Events.AnyModuleEvent{}])

    drained
  end

  @doc """
  I verify the CodeMonitor GenServer is running under the supervisor
  and has installed the trace on `:code_server`.
  """
  @spec monitor_running() :: pid()
  example monitor_running do
    pid = Process.whereis(GtBridge.CodeMonitor)
    assert is_pid(pid)
    assert Process.alive?(pid)

    # The trace must be installed on :code_server with our process as tracer.
    {:tracer, tracer} = :erlang.trace_info(Process.whereis(:code_server), :tracer)
    assert tracer == pid

    pid
  end

  @doc """
  I verify reloading an existing project-app module produces a recompile
  event.  Existing modules are already registered in their app's modules
  list, so `Application.get_application/1` returns the app and the
  monitor's filter accepts the load.
  """
  @spec recompile_broadcasts_for_project_module() :: [{atom(), module() | nil}]
  example recompile_broadcasts_for_project_module do
    monitor_running()

    target = GtBridge.Serializer
    assert Application.get_application(target) == :gt_bridge

    EventBroker.subscribe_me([%Events.AnyModuleEvent{}])

    :code.purge(target)
    :code.delete(target)
    {:module, ^target} = Code.ensure_loaded(target)

    drained =
      for _ <- 1..10 do
        receive do
          %Event{body: %ModuleEvent{} = ev} -> {ev.kind, ev.mod}
        after
          300 -> :empty
        end
      end
      |> Enum.reject(&(&1 == :empty))

    EventBroker.unsubscribe_me([%Events.AnyModuleEvent{}])

    project_events = Enum.filter(drained, fn {kind, m} -> kind == :recompiled and m == target end)

    assert project_events != [],
           "expected a :recompiled event for #{inspect(target)}, got #{inspect(drained)}"

    drained
  end

  @doc """
  I verify stdlib loads do NOT produce events: `project_module?/1`
  filters them out via `Application.get_application/1` not matching
  `project_apps/0`.
  """
  @spec non_project_module_filtered() :: :ok
  example non_project_module_filtered do
    monitor_running()

    EventBroker.subscribe_me([%Events.AnyModuleEvent{}])

    # Force-reload a stdlib module — its app is :elixir, never in project_apps.
    :code.purge(String.Chars.Atom)
    :code.delete(String.Chars.Atom)
    {:module, _} = Code.ensure_loaded(String.Chars.Atom)

    drained =
      for _ <- 1..5 do
        receive do
          %Event{body: %ModuleEvent{mod: m}} -> m
        after
          200 -> :empty
        end
      end
      |> Enum.reject(&(&1 == :empty))

    EventBroker.unsubscribe_me([%Events.AnyModuleEvent{}])

    assert String.Chars.Atom not in drained,
           "expected stdlib reload to be filtered, got #{inspect(drained)}"

    :ok
  end
end
