defmodule GtBridge.Xref do
  @moduledoc """
  I am a long-lived wrapper around OTP's `:xref` cross-reference server.

  The previous code in `GtBridge.Analysis` started a fresh `:xref` server,
  added the relevant app's ebin directory, ran one query, and stopped the
  server — for *every* call to `function_references/3` and
  `module_graph/1`. The `add_directory` step is the expensive part; xref
  parses every `.beam` file in the directory to build its edge index.
  Doing that per-query made interactive paths (C-n, the |> expander)
  perceptibly slow.

  I keep one xref server running for the lifetime of the BEAM, indexed
  against every loaded application's ebin at startup. Queries hit the
  in-memory index directly. When `BeamModuleRecompiled` fires (from
  `hot_reload/2` via the event bus), I call `:xref.replace_module/3` on
  just that module — so the index stays consistent with the live BEAM
  without rebuilding from scratch.

  ### Public API

  - `q/1` — run an xref query string and return its `:xref.q/2` result
  - `replace/1` — explicitly refresh one module's edges (also called
    automatically on `BeamModuleRecompiled`)

  ### Subscriptions

  I subscribe to `GtBridge.Events.AnyModuleEvent` and react to
  `:recompiled` events by calling `replace/1` on the affected module.
  """

  use GenServer

  alias EventBroker.Event
  alias GtBridge.Events
  alias GtBridge.Events.ModuleEvent

  ############################################################
  #                        Public API                        #
  ############################################################

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @xref_server :gtbridge_xref

  @spec q(charlist()) :: {:ok, list()} | {:error, term(), term()}
  def q(query) when is_list(query), do: GenServer.call(__MODULE__, {:q, query})

  @spec replace(module()) :: :ok
  def replace(mod) when is_atom(mod), do: GenServer.cast(__MODULE__, {:replace, mod})

  ############################################################
  #                    GenServer Callbacks                   #
  ############################################################

  @impl true
  def init(_) do
    case :xref.start(@xref_server) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Suppress xref's "N unresolved calls" warnings — they flood the REPL
    # with noise from third-party libs we don't care about.
    :xref.set_default(@xref_server, warnings: false, verbose: false)

    EventBroker.subscribe_me([%Events.AnyModuleEvent{}])

    # Defer the heavy add_directory loop to handle_continue so the
    # supervision tree finishes start-up immediately. Track ready
    # state so queries arriving during indexing return empty
    # immediately rather than blocking — better perceived startup
    # latency for the GT image.
    {:ok, %{ready: false}, {:continue, :index_apps}}
  end

  @impl true
  def handle_continue(:index_apps, state) do
    # Spawn the heavy indexing in a Task so our GenServer mailbox stays
    # free for queries. Queries arriving while the Task runs see
    # state.ready = false and return empty immediately, unblocking the
    # caller. xref serializes its own operations internally, so the
    # Task and any later xref calls coexist safely at the xref server.
    pid = self()

    Task.start(fn ->
      add_all_apps()
      GenServer.cast(pid, :indexing_done)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_cast(:indexing_done, state) do
    {:noreply, %{state | ready: true}}
  end

  @impl true
  def handle_call({:q, _query}, _from, %{ready: false} = state) do
    # Indexing still in progress. Return empty rather than make the
    # caller wait — features like C-n will show no results briefly
    # then work once handle_continue finishes.
    {:reply, {:ok, []}, state}
  end

  def handle_call({:q, query}, _from, state) do
    {:reply, :xref.q(@xref_server, query), state}
  end

  def handle_cast({:replace, mod}, state) do
    if state.ready, do: do_replace(mod)
    {:noreply, state}
  end

  @impl true
  def handle_info(%Event{body: %ModuleEvent{kind: :recompiled, mod: mod}}, %{ready: true} = state)
      when is_atom(mod) do
    do_replace(mod)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  defp add_all_apps do
    for {app, _, _} <- Application.loaded_applications() do
      case beam_path(app) do
        path when is_list(path) ->
          :xref.add_directory(@xref_server, path)

        _ ->
          :ok
      end
    end
  end

  defp do_replace(mod) do
    case :code.which(mod) do
      beam when is_list(beam) ->
        :xref.replace_module(@xref_server, mod, beam)

      _ ->
        :ok
    end
  end

  defp beam_path(app) do
    path = Application.app_dir(app, "ebin")
    if File.dir?(path), do: String.to_charlist(path), else: nil
  rescue
    _ -> nil
  end
end
