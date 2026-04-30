defmodule GtBridge.Views.MapGraph do
  @moduledoc """
  I display a map as a tree graph where each key points to its
  value, and nested maps expand recursively.
  """
  use GtBridge.View

  alias GtBridge.Phlow.Mondrian

  defview graph(map = %{}, builder) do
    {nodes, children} = build_graph(map)

    builder.mondrian()
    |> Mondrian.title("Map graph")
    |> Mondrian.priority(15)
    |> Mondrian.nodes(nodes)
    |> Mondrian.node_label(&inspect/1)
    |> Mondrian.edges(fn item -> Map.get(children, item, []) end)
    |> Mondrian.layout(:horizontal_tree)
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  # Returns {nodes, children_map} where nodes is a flat list of
  # domain objects (keys and values) and children_map encodes
  # the edges.  Duplicate values share a single node.
  @spec build_graph(map()) :: {list(), map()}
  defp build_graph(map) when is_map(map) do
    {nodes_reversed, children} = walk(map)
    {nodes_reversed |> Enum.reverse() |> Enum.uniq(), children}
  end

  @spec walk(map()) :: {list(), map()}
  defp walk(map) do
    Enum.reduce(map, {[], %{}}, fn {key, value}, {nodes, children} ->
      case value do
        %{} = nested ->
          {inner_nodes, inner_children} = walk(nested)
          new_children = Map.put(inner_children, key, Map.keys(nested))
          {inner_nodes ++ [key | nodes], new_children}

        _ ->
          {[value, key | nodes], Map.put(children, key, [value])}
      end
    end)
  end
end
