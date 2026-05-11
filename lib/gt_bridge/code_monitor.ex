defmodule GtBridge.CodeMonitor do
  @moduledoc """
  I am the sole publisher of `%ModuleEvent{kind: :recompiled}` events.

  I trace `:code_server.try_finish_module/6` and broadcast via
  `GtBridge.Events` for every project-app module that gets loaded —
  regardless of who triggered the load (`Code.compile_file`,
  `IEx.Helpers.recompile/0`, `:code.load_file/1`, external save +
  `iex> r/0`, hot-reload from any tool).

  The `:code_server` chokepoint means save handlers, refactor tools,
  and external IEx commands all flow through here without coordinating.

  ### Public API

  - `start_link/1` — start under the supervisor.
  """

  use GenServer

  alias GtBridge.Events
  alias GtBridge.Events.ModuleEvent

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  ############################################################
  #                    GenServer Callbacks                   #
  ############################################################

  @impl true
  def init(_) do
    pid = Process.whereis(:code_server) || raise "code_server not running"
    :erlang.trace(pid, true, [{:tracer, self()}, :call])
    :erlang.trace_pattern({:code_server, :try_finish_module, 6}, true, [:local])
    {:ok, %{}}
  end

  @impl true
  def handle_info({:trace, _pid, :call, {:code_server, :try_finish_module, args}}, state) do
    case args do
      [_first, mod | _] when is_atom(mod) ->
        if project_module?(mod) do
          Events.broadcast(%ModuleEvent{kind: :recompiled, mod: mod})
        end

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  defp project_module?(mod) do
    case Application.get_application(mod) do
      nil -> false
      app -> app in project_apps()
    end
  end

  defp project_apps do
    [Mix.Project.config()[:app] | GtBridge.Mix.path_dep_apps()]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end
end
