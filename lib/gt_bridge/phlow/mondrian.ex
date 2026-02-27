defmodule GtBridge.Phlow.Mondrian do
  @moduledoc """
  I am a Phlow Mondrian (graph) view specification.

  I serialize a node list, adjacency matrix, and layout name so that
  GT can render the graph via `GtPhlowMondrianViewSpecification`.

  ### Public API

  - `title/2`       — set the view title
  - `priority/2`    — set the view priority
  - `nodes/2`       — set the node list (list or 0-arity fn)
  - `node_label/2`  — set the node→label function
  - `node_object/2` — set the node→inspectable object function
  - `edges/2`       — set the item→children function
  - `layout/2`      — set the layout atom
  - `as_dict/1`     — serialize for GT transport
  """
  use TypedStruct

  typedstruct do
    field(:view_title, String.t(), default: "Unknown")
    field(:view_priority, integer(), default: 1)
    field(:nodes_callback, (-> list()) | nil, default: nil)
    field(:node_label, (any() -> String.t()) | nil, default: nil)
    field(:node_object, (any() -> any()) | nil, default: nil)
    field(:edges_callback, (any() -> list()) | nil, default: nil)
    field(:layout, atom(), default: :horizontal_tree)
  end

  @spec title(t(), String.t()) :: t()
  def title(self, title_text) do
    %__MODULE__{self | view_title: title_text}
  end

  @spec priority(t(), integer()) :: t()
  def priority(self, priority_value) do
    %__MODULE__{self | view_priority: priority_value}
  end

  @spec nodes(t(), list() | (-> list())) :: t()
  def nodes(self, items) when is_list(items) do
    %__MODULE__{self | nodes_callback: fn -> items end}
  end

  def nodes(self, fun) when is_function(fun, 0) do
    %__MODULE__{self | nodes_callback: fun}
  end

  @spec node_label(t(), (any() -> String.t())) :: t()
  def node_label(self, fun) do
    %__MODULE__{self | node_label: fun}
  end

  @doc """
  I set a function that maps each node to the object GT should
  inspect when the node is clicked.  When not set, clicking a
  node inspects the node itself.
  """
  @spec node_object(t(), (any() -> any())) :: t()
  def node_object(self, fun) do
    %__MODULE__{self | node_object: fun}
  end

  @spec edges(t(), (any() -> list())) :: t()
  def edges(self, fun) when is_function(fun, 1) do
    %__MODULE__{self | edges_callback: fun}
  end

  @spec layout(t(), atom()) :: t()
  def layout(self, layout_atom) do
    %__MODULE__{self | layout: layout_atom}
  end

  @spec as_dict(t()) :: map()
  def as_dict(self) do
    items = if self.nodes_callback, do: self.nodes_callback.(), else: []
    label_fn = self.node_label || (&inspect/1)

    index_map =
      items
      |> Enum.with_index()
      |> Map.new()

    nodes_data =
      Enum.map(items, fn item -> %{label: label_fn.(item)} end)

    adjacency =
      Enum.map(items, fn item ->
        children = if self.edges_callback, do: self.edges_callback.(item), else: []

        children
        |> Enum.map(&Map.get(index_map, &1))
        |> Enum.reject(&is_nil/1)
      end)

    layout_str =
      self.layout
      |> Atom.to_string()
      |> Macro.camelize()
      |> downcase_first()

    base = %{
      title: self.view_title,
      priority: self.view_priority,
      viewName: "GtPhlowMondrianViewSpecification",
      dataTransport: 2,
      nodes: nodes_data,
      adjacency: adjacency,
      layout: layout_str
    }

    if self.node_object do
      Map.put(base, :objects, Enum.map(items, self.node_object))
    else
      base
    end
  end

  defp downcase_first(<<first::utf8, rest::binary>>) do
    String.downcase(<<first::utf8>>) <> rest
  end

  defp downcase_first(str), do: str
end
