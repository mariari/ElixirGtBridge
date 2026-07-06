defmodule GtBridge.Analysis.LoadedModules do
  @moduledoc """
  I maintain the set of every loaded Elixir module, keyed by its dotted
  name string (e.g. "GtBridge.Eval") and carrying its module atom and
  owning application.  I am populated initially from
  `:application.get_key/2` for every loaded application and maintained
  additively by EventBroker `%ModuleEvent{}` events.

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

  @doc "I return the module atoms belonging to `app`."
  @spec modules_for_app(atom()) :: [module()]
  def modules_for_app(app), do: :ets.select(@table, [{{:_, :"$1", app}, [], [:"$1"]}])

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  ############################################################
  #                    GenServer Callbacks                   #
  ############################################################

  @impl true
  def init(_) do
    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true
    ])

    populate()
    EventBroker.subscribe_me([%Events.AnyModuleEvent{}])
    {:ok, []}
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

  defp populate do
    for {app, _, _} <- Application.loaded_applications(),
        {:ok, mods} <- [:application.get_key(app, :modules)],
        mod <- mods do
      :ets.insert(@table, {inspect(mod), mod, app})
    end

    :ok
  end

  # `Application.get_application/1` resolves via the app spec's module
  # list, frozen at load — a live-recompiled new module isn't in it and
  # comes back nil, so I fall back to the module's beam location under an
  # app's ebin directory.
  defp app_of(mod) do
    case Application.get_application(mod) do
      app when is_atom(app) and not is_nil(app) -> app
      _ -> app_from_beam(mod)
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
end
