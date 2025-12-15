defmodule GtBridge.Phlow.ColumnedTree do
  @moduledoc """
  A Phlow columned tree view specification.

  Displays a hierarchical tree with multiple columns in GT's inspector.
  """
  use TypedStruct

  alias GtBridge.Phlow.Column

  typedstruct do
    field(:view_title, String.t(), default: "Unknown")
    field(:view_priority, integer(), default: 1)
    field(:items_callback, (-> list()) | nil, default: nil)
    field(:columns, list(Column.t()), default: [])
    field(:children_callback, (any() -> list()) | nil, default: nil)
  end

  @doc """
  Set the title of the view.
  """
  @spec title(t(), String.t()) :: t()
  def title(self, title_text) do
    %__MODULE__{self | view_title: title_text}
  end

  @doc """
  Set the priority of the view.
  """
  @spec priority(t(), integer()) :: t()
  def priority(self, priority_value) do
    %__MODULE__{self | view_priority: priority_value}
  end

  @doc """
  Set the items to display. Can be a list or a function that returns a list.
  """
  @spec items(t(), list() | (-> list())) :: t()
  def items(self, items_list) when is_list(items_list) do
    %__MODULE__{self | items_callback: fn -> items_list end}
  end

  def items(self, items_fn) when is_function(items_fn, 0) do
    %__MODULE__{self | items_callback: items_fn}
  end

  @doc """
  Set the children function that returns children for a given item.
  """
  @spec children(t(), (any() -> list())) :: t()
  def children(self, children_fn) do
    %__MODULE__{self | children_callback: children_fn}
  end

  @doc """
  Add a column to the view.
  """
  @spec column(t(), String.t(), (any() -> String.t()) | nil) :: t()
  def column(self, title, format_fn \\ nil) do
    col = Column.new(title)
    col = if format_fn, do: Column.format(col, format_fn), else: col
    %__MODULE__{self | columns: self.columns ++ [col]}
  end

  @doc """
  Convert the columned tree view to a dictionary format for serialization to GT.
  """
  @spec as_dict(t()) :: map()
  def as_dict(self) do
    items_data =
      if self.items_callback do
        self.items_callback.()
      else
        []
      end

    # Format items recursively with children
    formatted_data = format_tree_items(items_data, self)

    %{
      title: self.view_title,
      priority: self.view_priority,
      viewName: "GtPhlowColumnedTreeViewSpecification",
      dataTransport: 2,
      itemsCount: length(items_data),
      columns: Enum.map(self.columns, &Column.as_dict/1),
      items: formatted_data
    }
  end

  # Helper function to recursively format tree items with their children
  defp format_tree_items(items, self) do
    Enum.map(items, fn item ->
      # Format the column values for this item
      values =
        Enum.map(self.columns, fn col ->
          Column.format_item(col, item)
        end)

      # Get children for this item if callback is provided
      children =
        if self.children_callback do
          child_items = self.children_callback.(item)
          format_tree_items(child_items, self)
        else
          []
        end

      # Return a map with values and children
      %{
        values: values,
        children: children
      }
    end)
  end
end
