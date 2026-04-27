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

  I keep one xref server running for the lifetime of the BEAM. Indexing
  runs in a background `:low`-priority Task so it yields to any
  normal-priority work — eager add_directory on every loaded app
  contends with the OTP code server enough to cascade GT's startup
  module_details fan-out into 5s eval timeouts at normal priority.
  Queries arriving before indexing completes return `{:ok, []}` rather
  than blocking. When `BeamModuleRecompiled` fires (from `hot_reload/2`
  via the event bus), I call `:xref.replace_module/3` on just that
  module — so the index stays consistent with the live BEAM without
  rebuilding from scratch.

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

  @doc """
  I am true once the initial indexing pass has completed.  Until then
  every `q/1` returns `{:ok, []}` per the moduledoc contract.
  """
  @spec ready?() :: boolean()
  def ready?, do: GenServer.call(__MODULE__, :ready?)

  @doc """
  Block the caller until indexing finishes (or `timeout_ms` elapses).
  Useful from test setup so assertions about xref data don't race
  the background indexer.  Returns `:ok` when ready, exits with
  `:timeout` like any other `GenServer.call/3` if the deadline lapses.

  Already-ready replies immediately; otherwise the caller is parked
  on a deferred reply and woken from `handle_cast(:indexing_done, _)`.
  """
  @spec wait_until_ready(timeout()) :: :ok
  def wait_until_ready(timeout_ms \\ 30_000) do
    GenServer.call(__MODULE__, :wait_until_ready, timeout_ms)
  end

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

    # Kick off indexing immediately via handle_continue so init returns
    # straight away. The Task itself runs at :low priority so it
    # yields to any eval handler that wants the scheduler.
    {:ok, %{ready: false, waiters: []}, {:continue, :index_apps}}
  end

  @impl true
  def handle_continue(:index_apps, state) do
    pid = self()

    Task.start(fn ->
      Process.flag(:priority, :low)
      add_all_apps()
      GenServer.cast(pid, :indexing_done)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:q, _query}, _from, %{ready: false} = state) do
    # Indexing still pending or in progress. Return empty rather than
    # block — features like C-n will show no results briefly then
    # work once indexing finishes.
    {:reply, {:ok, []}, state}
  end

  def handle_call({:q, query}, _from, state) do
    {:reply, :xref.q(@xref_server, query), state}
  end

  def handle_call(:ready?, _from, state), do: {:reply, state.ready, state}

  def handle_call(:wait_until_ready, _from, %{ready: true} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:wait_until_ready, from, state) do
    {:noreply, %{state | waiters: [from | state.waiters]}}
  end

  @impl true
  def handle_cast(:indexing_done, state) do
    Enum.each(state.waiters, &GenServer.reply(&1, :ok))
    {:noreply, %{state | ready: true, waiters: []}}
  end

  def handle_cast({:replace, mod}, state) do
    if state.ready, do: do_replace(mod)
    {:noreply, state}
  end

  @impl true
  def handle_info(
        %Event{body: %ModuleEvent{kind: :recompiled, mod: mod}},
        %{ready: true} = state
      )
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
