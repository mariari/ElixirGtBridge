defmodule GtBridge.Views.MapGraph do
  @moduledoc """
  I display a map as a tree graph where each key points to its
  value, and nested maps expand recursively.
  """
  use GtBridge.View

  alias GtBridge.Phlow.Mondrian

  defview graph(map = %{}, builder) do
    {all_nodes, _top} = build_nodes(map)

    builder.mondrian()
    |> Mondrian.title("Map graph")
    |> Mondrian.priority(15)
    |> Mondrian.nodes(all_nodes)
    |> Mondrian.node_label(fn %{label: label} -> label end)
    |> Mondrian.node_object(fn %{value: value} -> value end)
    |> Mondrian.edges(fn %{children: children} -> children end)
    |> Mondrian.layout(:horizontal_tree)
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  # Returns {all_nodes, top_level_nodes}.
  # Each node is %{label: string, value: original, children: [node], id: ref}.
  # The id ensures uniqueness in the index map even when two
  # nodes share the same label (e.g. two values of "1").
  @spec build_nodes(map()) :: {list(map()), list(map())}
  defp build_nodes(map) when is_map(map) do
    Enum.reduce(map, {[], []}, fn {key, value}, {all_acc, top_acc} ->
      case value do
        %{} = nested ->
          {nested_all, nested_top} = build_nodes(nested)
          key_node = %{label: inspect(key), value: key, children: nested_top, id: make_ref()}
          {all_acc ++ [key_node | nested_all], top_acc ++ [key_node]}

        _ ->
          val_node = %{label: inspect(value), value: value, children: [], id: make_ref()}
          key_node = %{label: inspect(key), value: key, children: [val_node], id: make_ref()}
          {all_acc ++ [key_node, val_node], top_acc ++ [key_node]}
      end
    end)
  end
end
