defmodule GtBridge.CacheReaper do
  @moduledoc """
  I own the named ETS table that backs all GtBridge derived-state caches and
  invalidate per-module entries when the module recompiles.

  Cache consumers (styler call_sites, alias maps, function records, doc
  fetches, source paths, module→app lookups) read and write this table
  directly via `:ets`. I do not mediate reads or writes — I only react to
  `%ModuleEvent{kind: :recompiled | :removed}` from the EventBroker by
  deleting every entry tagged with the affected module.

  Cache key shape places the module second so a single match-delete reaches
  every entry for a module regardless of the entry's `:kind`:

      {:call_sites, mod, source_hash}
      {:alias_map,  mod, source_hash}
      {:functions,  mod, source_hash}
      {:docs,       mod}
      {:source_file, mod}
      {:module_app, mod}

  ### Public API

  - `start_link/1` — supervised start
  - `table/0` — name of the ETS table for cache consumers
  """

  use GenServer

  alias EventBroker.Event
  alias GtBridge.Events
  alias GtBridge.Events.ModuleEvent

  @table :gtbridge_cache

  ############################################################
  #                        Public API                        #
  ############################################################

  @spec table() :: atom()
  def table, do: @table

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
      read_concurrency: true,
      write_concurrency: true
    ])

    EventBroker.subscribe_me([%Events.AnyModuleEvent{}])
    {:ok, []}
  end

  @impl true
  def handle_info(%Event{body: %ModuleEvent{} = body}, state) do
    invalidate(body)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  defp invalidate(%ModuleEvent{mod: nil}), do: :ok

  defp invalidate(%ModuleEvent{kind: :compile_failed}), do: :ok

  defp invalidate(%ModuleEvent{mod: mod}) when is_atom(mod) do
    :ets.match_delete(@table, {{:_, mod, :_}, :_})
    :ets.match_delete(@table, {{:_, mod}, :_})
    :ok
  end
end
