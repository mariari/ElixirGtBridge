defmodule GtBridge.Analysis.LoadedModules do
  @moduledoc """
  I maintain the set of every loaded module, keyed by its name as
  `inspect/1` renders it ("GtBridge.Eval", ":erlang") and carrying its
  module atom and owning application.  I am populated initially from
  `:application.get_key/2` for every loaded application plus whatever
  the VM has already loaded, and maintained additively by EventBroker
  `%ModuleEvent{}` events.

  This is the FRP shape the bridge is moving toward: derived state (the
  "modules currently loaded" projection) maintained by the
  infrastructure (events) instead of recomputed by every consumer.
  `:application.get_key/2` is a static snapshot frozen at app load, so a
  module born from a live recompile (a new file, or a nested module from
  `typedstruct module:`) never appears in it — but it does arrive here as
  a `:recompiled` fact.  That is why module enumeration
  (`Analysis.all_module_names/0`, the private `modules/1`, and through
  them the spotter and the module browser) reads me rather than
  `get_key` directly.

  ### Public API

  - `loaded?/1` — true when the named module is in my set (O(1))
  - `all_names/0` — every loaded module's dotted-name string
  - `modules_for_app/1` — the module atoms belonging to `app`
  - `sync/0` — enter modules loaded outside the bridge's pipeline
  - `full_sync/0` — sync both directions, retracting vanished modules
  """

  use GenServer

  alias EventBroker.Event
  alias GtBridge.Events
  alias GtBridge.Events.ModuleEvent

  @table :gtbridge_loaded_modules

  ############################################################
  #                        Public API                        #
  ############################################################

  @doc """
  I am true when `name` (a string of the dotted Elixir module name,
  e.g. "GtBridge.Eval") is currently loaded in the BEAM.
  """
  @spec loaded?(String.t()) :: boolean()
  def loaded?(name), do: :ets.member(@table, name)

  @doc "I return every loaded module's dotted-name string."
  @spec all_names() :: [String.t()]
  def all_names, do: :ets.select(@table, [{{:"$1", :_, :_}, [], [:"$1"]}])

  @doc """
  I return every loaded module's dotted name starting with `prefix`, in
  sorted order, by walking my key range rather than filtering every name.

  Erlang modules are stored as `inspect/1` renders them, so ask for them
  with a `":"`-prefixed hint.
  """
  @spec names_with_prefix(String.t()) :: [String.t()]
  def names_with_prefix(prefix) do
    # `:ets.next/2` is strictly greater, so an exact hit needs asking for.
    exact = if :ets.member(@table, prefix), do: [prefix], else: []
    exact ++ walk_prefix(:ets.next(@table, prefix), prefix, [])
  end

  @doc "I return the module atoms belonging to `app`."
  @spec modules_for_app(atom()) :: [module()]
  def modules_for_app(app), do: :ets.select(@table, [{{:_, :"$1", app}, [], [:"$1"]}])

  @doc """
  I diff the BEAM's loaded modules against my set and broadcast a
  `:recompiled` fact for each one that arrived outside the bridge's
  pipeline (iex `defmodule`, dynamic codegen, eval snippets). Other
  projections hear the facts through their normal subscriptions; to
  every consumer a discovered module is indistinguishable from a
  recompiled one. Returns the newly entered module names.
  """
  @spec sync() :: [String.t()]
  def sync, do: GenServer.call(__MODULE__, :sync)

  @doc """
  I reconcile in both directions: enter appearances like `sync/0`, and
  retract modules that no longer exist (not loaded, not in any loaded
  app's spec, not loadable), broadcasting `:source_removed` for each.
  Absence from `:code.all_loaded/0` alone is ambiguous (the BEAM loads
  lazily), so retraction cross-checks the app specs and the code
  server too - heavier than `sync/0`, so I run at bridge connection,
  not per eval.
  """
  @spec full_sync() :: %{added: [String.t()], removed: [String.t()]}
  def full_sync, do: GenServer.call(__MODULE__, :full_sync)

  @doc """
  I enter facts without blocking the caller: `sync_async/0` after
  every eval. Entering
  facts is fire-and-forget; a blocking call here serializes every
  eval through me and lets a busy queue kill the SSE stream's init
  on its call timeout.
  """
  @spec sync_async() :: :ok
  def sync_async, do: GenServer.cast(__MODULE__, :sync)

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  ############################################################
  #                    GenServer Callbacks                   #
  ############################################################

  @impl true
  def init(_) do
    # `:ordered_set` so `names_with_prefix/1` can walk a key range; costs
    # `loaded?/1` O(1) -> O(log n).
    :ets.new(@table, [
      :ordered_set,
      :public,
      :named_table,
      read_concurrency: true
    ])

    populate()
    EventBroker.subscribe_me([%Events.AnyModuleEvent{}])
    {:ok, []}
  end

  @impl true
  def handle_call(:sync, _from, state), do: {:reply, do_sync(), state}

  @impl true
  def handle_call(:full_sync, _from, state),
    do: {:reply, %{added: do_sync(), removed: retract_vanished()}, state}

  @impl true
  def handle_cast(:sync, state) do
    do_sync()
    {:noreply, state}
  end

  @impl true
  def handle_info(%Event{body: %ModuleEvent{kind: :recompiled, mod: mod}}, state)
      when is_atom(mod) and not is_nil(mod) do
    :ets.insert(@table, {inspect(mod), mod, app_of(mod)})
    {:noreply, state}
  end

  def handle_info(%Event{body: %ModuleEvent{kind: :source_removed, mod: mod}}, state)
      when is_atom(mod) and not is_nil(mod) do
    :ets.delete(@table, inspect(mod))
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  defp walk_prefix(:"$end_of_table", _prefix, acc), do: Enum.reverse(acc)

  defp walk_prefix(key, prefix, acc) do
    if String.starts_with?(key, prefix),
      do: walk_prefix(:ets.next(@table, key), prefix, [key | acc]),
      else: Enum.reverse(acc)
  end

  defp populate do
    for entry <- spec_entries(), do: :ets.insert(@table, entry)
    # App specs miss whatever the running VM loaded without one -- `erts`
    # is a loaded application under `mix run` but not under `mix test`,
    # so `:erlang` would come and go with the environment.  Seeding from
    # the VM too makes coverage the same everywhere.  Unlike `do_sync/0`
    # this stays quiet: nobody has subscribed yet at init.
    for {mod, _file} <- :code.all_loaded(),
        name = inspect(mod),
        not String.starts_with?(name, ":elixir_compiler_") do
      :ets.insert(@table, {name, mod, app_of(mod)})
    end

    :ok
  end

  # Every module vouched for by a loaded application's spec, in table
  # entry shape.
  @spec spec_entries() :: [{String.t(), module(), atom()}]
  defp spec_entries do
    for {app, _, _} <- Application.loaded_applications(),
        {:ok, mods} <- [:application.get_key(app, :modules)],
        mod <- mods,
        do: {inspect(mod), mod, app}
  end

  # I record the missed modules directly (so back-to-back syncs don't
  # re-announce) and broadcast each as a fact for the other projections.
  # `:elixir_compiler_N` workspaces are the compiler's own scaffolding,
  # not modules-as-facts; a fresh one appears on every compiling eval.
  @spec do_sync() :: [String.t()]
  defp do_sync do
    for {mod, _file} <- :code.all_loaded(),
        name = inspect(mod),
        not String.starts_with?(name, ":elixir_compiler_"),
        not :ets.member(@table, name) do
      :ets.insert(@table, {name, mod, app_of(mod)})
      Events.broadcast(%ModuleEvent{kind: :recompiled, mod: mod})
      name
    end
  end

  # A module still in my set but not loaded, not vouched for by any
  # loaded app's spec, and not loadable (:code.which :non_existing) was
  # deleted out-of-band (bare :code.delete, external purge). The spec
  # check matters: Mix prunes unused apps' code paths at boot, so their
  # modules are unloadable yet very much exist. The final :code.which
  # keeps a dynamic module whose beam was persisted to an ebin.
  @spec retract_vanished() :: [String.t()]
  defp retract_vanished do
    existing = existing_names()

    for name <- all_names(),
        not MapSet.member?(existing, name),
        [{^name, mod, _app}] <- [:ets.lookup(@table, name)],
        :code.which(mod) == :non_existing do
      :ets.delete(@table, name)
      Events.broadcast(%ModuleEvent{kind: :source_removed, mod: mod})
      name
    end
  end

  # Everything that exists: loaded now, or listed in a loaded
  # application's spec (the BEAM loads lazily, so unloaded is not gone).
  @spec existing_names() :: MapSet.t(String.t())
  defp existing_names do
    loaded = for {mod, _file} <- :code.all_loaded(), do: inspect(mod)
    spec_listed = for {name, _mod, _app} <- spec_entries(), do: name
    MapSet.new(loaded ++ spec_listed)
  end

  @doc """
  I resolve the application a module belongs to, falling back where the
  raw `Application.get_application/1` returns nil.

  `get_application/1` reads the app spec's module list, frozen at load,
  so a live-recompiled new module comes back nil.  `app_from_beam/1`
  matches `:code.which` against ebin dirs, but a `Code.compile_file`'d
  module reports its source path (or ""), never an ebin beam.
  `app_from_source/1` places a new file in a path dep by its source
  location.  Anything still unplaced (Erlang internals, eval-only
  modules) falls back to the current application rather than nil, so it
  surfaces under the project being worked on instead of vanishing.

  This is what the GT-side Application button resolves through, so a
  brand-new module lands on its app instead of nowhere.
  """
  @spec app_of(module()) :: atom() | nil
  def app_of(mod) do
    case Application.get_application(mod) do
      app when is_atom(app) and not is_nil(app) -> app
      _ -> app_from_beam(mod) || app_from_source(mod) || current_app()
    end
  end

  defp app_from_beam(mod) do
    with beam when is_list(beam) <- :code.which(mod) do
      beam_str = List.to_string(beam)

      Enum.find_value(Application.loaded_applications(), fn {app, _, _} ->
        ebin = safe_ebin(app)
        ebin && String.starts_with?(beam_str, ebin) && app
      end)
    else
      _ -> nil
    end
  end

  # app_dir raises ArgumentError for an app whose lib dir can't be
  # resolved (loaded spec without a directory, e.g. pruned code paths).
  defp safe_ebin(app) do
    Application.app_dir(app, "ebin")
  rescue
    ArgumentError -> nil
  end

  # A path dep owns the source files under its checked-out tree, so a
  # new module there maps to that app by its source location — the same
  # mapping the hot-reload pipeline uses to place the beam.  Needs Mix;
  # in a release (no Mix project) there's nothing to map, so rescue nil.
  defp app_from_source(mod) do
    with src when is_binary(src) <- GtBridge.Resolve.source_file(mod) do
      abs = Path.expand(src)

      Enum.find_value(Mix.Project.deps_paths(), fn {app, dep_path} ->
        String.starts_with?(abs, Path.expand(dep_path) <> "/") && app
      end)
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # The application the bridge is embedded in — the user's own project,
  # whatever it is — used as the last-resort owner for an otherwise
  # unplaceable module.  nil in a release with no Mix project loaded.
  defp current_app do
    Mix.Project.config()[:app]
  rescue
    _ -> nil
  end
end
