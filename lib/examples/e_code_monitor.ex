defmodule Examples.ECodeMonitor do
  @moduledoc """
  I am examples for `GtBridge.CodeMonitor`, the sole publisher of
  `%ModuleEvent{kind: :recompiled}` on the bridge's EventBroker bus.

  Examples compose: `monitor_pid` is the leaf; every later example
  builds on the verified-running monitor.  `recompile_event` returns
  the events drained from a real reload, and the negative case
  (`non_project_module_filtered`) inherits that proof of life before
  exercising the filter.
  """

  use ExExample

  import ExUnit.Assertions

  alias EventBroker.Event
  alias GtBridge.Events
  alias GtBridge.Events.ModuleEvent

  # `monitor_pid` is a pure read of supervised state, cache it.
  # The reload-driving examples have real side effects, re-run.
  def rerun?(:monitor_pid), do: false
  def rerun?(_), do: true

  @doc """
  I assert the supervised CodeMonitor pid is alive AND has the
  trace installed on `:code_server` with itself as tracer.  Every
  later example builds on this. The trace is what makes the bus
  fire, so all downstream behavior is contingent on it.
  """
  @spec monitor_pid() :: pid()
  example monitor_pid do
    pid = Process.whereis(GtBridge.CodeMonitor)
    assert is_pid(pid)
    assert Process.alive?(pid)

    {:tracer, ^pid} = :erlang.trace_info(Process.whereis(:code_server), :tracer)

    pid
  end

  @doc """
  I reload an existing project module, drain the bus, and return the
  events I saw.  Building block for downstream examples; the events
  list is what a real save looks like once the chain is working.
  """
  @spec recompile_event() :: [{atom(), module() | nil}]
  example recompile_event do
    monitor_pid()
    target = GtBridge.Serializer
    assert Application.get_application(target) == :gt_bridge

    drained =
      with_subscription(fn ->
        :code.purge(target)
        :code.delete(target)
        {:module, ^target} = Code.ensure_loaded(target)
        drain(300)
      end)

    assert Enum.any?(drained, fn {kind, m} -> kind == :recompiled and m == target end),
           "expected a :recompiled event for #{inspect(target)}, got #{inspect(drained)}"

    drained
  end

  @doc """
  I exercise the filter side: stdlib reloads must NOT produce events.
  Composes on `recompile_event` (that proves the bus fires when it
  should); this proves it stays silent when it shouldn't.
  """
  @spec non_project_module_filtered() :: [{atom(), module() | nil}]
  example non_project_module_filtered do
    recompile_event()

    drained =
      with_subscription(fn ->
        :code.purge(String.Chars.Atom)
        :code.delete(String.Chars.Atom)
        {:module, _} = Code.ensure_loaded(String.Chars.Atom)
        drain(200)
      end)

    refute String.Chars.Atom in Enum.map(drained, &elem(&1, 1)),
           "expected stdlib reload to be filtered, got #{inspect(drained)}"

    drained
  end

  defp with_subscription(fun) do
    EventBroker.subscribe_me([%Events.AnyModuleEvent{}])

    try do
      fun.()
    after
      EventBroker.unsubscribe_me([%Events.AnyModuleEvent{}])
    end
  end

  defp drain(timeout_ms) do
    drain([], timeout_ms)
  end

  defp drain(acc, timeout_ms) do
    receive do
      %Event{body: %ModuleEvent{} = ev} -> drain([{ev.kind, ev.mod} | acc], timeout_ms)
    after
      timeout_ms -> Enum.reverse(acc)
    end
  end
end
