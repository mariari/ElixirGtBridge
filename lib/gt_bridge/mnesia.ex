defmodule GtBridge.Mnesia do
  # mnesia is an optional runtime dependency — not available at compile time
  @compile {:no_warn_undefined, [:mnesia]}
  @moduledoc """
  I expose Mnesia table introspection to GT.

  All my functions degrade gracefully when Mnesia is not running —
  they return empty results so view rendering doesn't fail when
  the user's BEAM has no Mnesia configured.
  """

  @doc "I return mnesia table info for the table list.
  Returns an empty list when mnesia is not started."
  @spec tables() :: [map()]
  def tables do
    if Code.ensure_loaded?(:mnesia) and :mnesia.system_info(:is_running) == :yes do
      :mnesia.system_info(:tables)
      |> Enum.reject(&(&1 == :schema))
      |> Enum.map(fn t ->
        %{
          name: Atom.to_string(t),
          size: :mnesia.table_info(t, :size),
          type: Atom.to_string(:mnesia.table_info(t, :type)),
          attrs: Enum.map_join(:mnesia.table_info(t, :attributes), ", ", &Atom.to_string/1)
        }
      end)
      |> Enum.sort_by(& &1.name)
    else
      []
    end
  end

  @doc "I return schema info for a mnesia table.
  Returns an empty map when mnesia is not running."
  @spec schema(atom()) :: map()
  def schema(table) do
    if Code.ensure_loaded?(:mnesia) and :mnesia.system_info(:is_running) == :yes do
      %{
        type: :mnesia.table_info(table, :type),
        size: :mnesia.table_info(table, :size),
        memory: :mnesia.table_info(table, :memory),
        storage: :mnesia.table_info(table, :storage_type),
        record_name: :mnesia.table_info(table, :record_name),
        attributes:
          Enum.map_join(:mnesia.table_info(table, :attributes), ", ", &Atom.to_string/1),
        indexes: inspect(:mnesia.table_info(table, :index)),
        access_mode: :mnesia.table_info(table, :access_mode),
        load_order: :mnesia.table_info(table, :load_order)
      }
    else
      %{}
    end
  end

  @doc "I return records from a mnesia table."
  @spec records(atom(), non_neg_integer()) :: [list()]
  def records(table, limit \\ 500) do
    attrs = :mnesia.table_info(table, :attributes)

    :mnesia.dirty_all_keys(table)
    |> Enum.take(limit)
    |> Enum.flat_map(fn key ->
      :mnesia.dirty_read(table, key)
      |> Enum.map(fn rec ->
        values = rec |> Tuple.to_list() |> tl()

        Enum.zip(attrs, values)
        |> Enum.map(fn {a, v} -> {Atom.to_string(a), inspect(v)} end)
      end)
    end)
  end
end
