defmodule GtBridge.Phlow.ColumnedList do
  @moduledoc """
  A Phlow columned list view specification.

  Displays a list with multiple columns in GT's inspector.
  """
  use TypedStruct

  alias GtBridge.Phlow.Column

  typedstruct do
    field(:view_title, String.t(), default: "Unknown")
    field(:view_priority, integer(), default: 1)
    field(:items_callback, (-> list()) | nil, default: nil)
    field(:columns, list(Column.t()), default: [])
    field(:send_callback, (any() -> any()) | nil, default: nil)
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
  Add a column to the view.
  """
  @spec column(t(), String.t(), (any() -> String.t()) | nil) :: t()
  def column(self, title, format_fn \\ nil) do
    col = Column.new(title)
    col = if format_fn, do: Column.format(col, format_fn), else: col
    %__MODULE__{self | columns: self.columns ++ [col]}
  end

  @doc """
  I transform each item before sending to GT on click-through.
  """
  @spec send(t(), (any() -> any())) :: t()
  def send(self, send_fn) when is_function(send_fn, 1) do
    %__MODULE__{self | send_callback: send_fn}
  end

  @doc """
  Convert the columned list view to a dictionary format for serialization to GT.
  """
  @spec as_dict(t()) :: map()
  def as_dict(self) do
    items_data =
      if self.items_callback do
        self.items_callback.()
      else
        []
      end

    formatted_data =
      Enum.map(items_data, fn item ->
        Enum.map(self.columns, fn col ->
          Column.format_item(col, item)
        end)
      end)

    %{
      title: self.view_title,
      priority: self.view_priority,
      viewName: "GtPhlowColumnedListViewSpecification",
      dataTransport: 2,
      itemsCount: length(items_data),
      columns: Enum.map(self.columns, &Column.as_dict/1),
      items: formatted_data,
      rawItems:
        if(self.send_callback,
          do: Enum.map(items_data, self.send_callback),
          else: items_data
        )
    }
  end
end
