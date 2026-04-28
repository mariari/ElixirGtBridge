defmodule GtBridge.Analysis.LoadedModules do
  @moduledoc """
  I maintain the set of every loaded Elixir module name (e.g.
  "GtBridge.Eval"), populated initially from
  `:application.get_key/2` for every loaded application and
  maintained additively by EventBroker `%ModuleEvent{}` events.

  Consumers query me through `loaded?/1` for an O(1) ETS read —
  no recompute per call.  Module recompiles add to my set; module
  removals delete from it.

  This is the FRP shape the bridge is moving toward: derived state
  (the "modules currently loaded" projection) maintained by the
  infrastructure (events) instead of recomputed by every consumer.
  Today only `Analysis.unresolved_modules/2` reads me; future
  consumers (e.g. a wider styler that flags unresolved struct
  literals or behaviours) plug in identically.

  ### Public API

  - `loaded?/1` — true when the named module is in my set.
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
    :ets.insert(@table, {inspect(mod)})
    {:noreply, state}
  end

  def handle_info(%Event{body: %ModuleEvent{kind: :removed, mod: mod}}, state)
      when is_atom(mod) and not is_nil(mod) do
    :ets.delete(@table, inspect(mod))
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  defp populate do
    Application.loaded_applications()
    |> Enum.flat_map(fn {app, _, _} ->
      case :application.get_key(app, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end
    end)
    |> Enum.each(fn mod -> :ets.insert(@table, {inspect(mod)}) end)
  end
end
