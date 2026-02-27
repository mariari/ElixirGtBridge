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
end
