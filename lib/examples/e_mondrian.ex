defmodule Examples.EMondrian do
  import ExUnit.Assertions

  alias GtBridge.Phlow.Mondrian

  @spec simple_graph() :: map()
  def simple_graph() do
    nodes = [:a, :b, :c, :d]

    children = %{
      a: [:b, :c],
      b: [:d],
      c: [],
      d: []
    }

    dict =
      GtBridge.Phlow.Builder.mondrian()
      |> Mondrian.title("Dependencies")
      |> Mondrian.priority(5)
      |> Mondrian.nodes(nodes)
      |> Mondrian.node_label(&Atom.to_string/1)
      |> Mondrian.edges(fn node -> Map.get(children, node, []) end)
      |> Mondrian.layout(:horizontal_tree)
      |> Mondrian.as_dict()

    assert dict.viewName == "GtPhlowMondrianViewSpecification"
    assert length(dict.nodes) == 4
    assert Enum.at(dict.nodes, 0) == %{label: "a"}
    assert Enum.at(dict.adjacency, 0) == [1, 2]
    assert Enum.at(dict.adjacency, 1) == [3]
    assert Enum.at(dict.adjacency, 2) == []
    assert dict.layout == "horizontalTree"

    dict
  end

  @spec default_labels() :: map()
  def default_labels() do
    dict =
      GtBridge.Phlow.Builder.mondrian()
      |> Mondrian.nodes([1, 2, 3])
      |> Mondrian.as_dict()

    assert Enum.at(dict.nodes, 0) == %{label: "1"}

    dict
  end

  @spec map_graph_flat() :: map()
  def map_graph_flat() do
    view = GtBridge.Views.MapGraph.graph(%{a: 1}, GtBridge.Phlow.Builder)
    dict = Mondrian.as_dict(view)

    assert dict.viewName == "GtPhlowMondrianViewSpecification"
    assert length(dict.nodes) == 2

    labels = Enum.map(dict.nodes, & &1.label)
    assert ":a" in labels
    assert "1" in labels

    # Key points to value: find :a's index, check its adjacency
    a_idx = Enum.find_index(dict.nodes, &(&1.label == ":a"))
    v_idx = Enum.find_index(dict.nodes, &(&1.label == "1"))
    assert Enum.at(dict.adjacency, a_idx) == [v_idx]
    assert Enum.at(dict.adjacency, v_idx) == []

    dict
  end

  @spec map_graph_nested() :: map()
  def map_graph_nested() do
    view = GtBridge.Views.MapGraph.graph(%{x: %{y: 1}}, GtBridge.Phlow.Builder)
    dict = Mondrian.as_dict(view)

    assert length(dict.nodes) == 3

    labels = Enum.map(dict.nodes, & &1.label)
    assert ":x" in labels
    assert ":y" in labels
    assert "1" in labels

    x_idx = Enum.find_index(dict.nodes, &(&1.label == ":x"))
    y_idx = Enum.find_index(dict.nodes, &(&1.label == ":y"))
    v_idx = Enum.find_index(dict.nodes, &(&1.label == "1"))

    # :x → :y → 1
    assert Enum.at(dict.adjacency, x_idx) == [y_idx]
    assert Enum.at(dict.adjacency, y_idx) == [v_idx]
    assert Enum.at(dict.adjacency, v_idx) == []

    dict
  end

  @spec map_graph_view_registered() :: map()
  def map_graph_view_registered() do
    GtBridge.View.register(GtBridge.Views.MapGraph)
    views = GtBridge.Views.lookup(GtBridge.Views, Map)
    assert MapSet.size(views) >= 1
    assert MapSet.member?(views, {GtBridge.Views.MapGraph, :graph})
  end
end
