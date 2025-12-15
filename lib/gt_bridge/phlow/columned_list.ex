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

    require Logger
    Logger.info("ColumnedList items_data: #{inspect(items_data)}")
    Logger.info("ColumnedList columns: #{inspect(self.columns)}")

    # Format items for each column - each row should be a list of formatted string values
    formatted_data =
      Enum.map(items_data, fn item ->
        row_values =
          Enum.map(self.columns, fn col ->
            Column.format_item(col, item)
          end)

        Logger.info("Row values: #{inspect(row_values)}")
        row_values
      end)

    result = %{
      title: self.view_title,
      priority: self.view_priority,
      viewName: "GtPhlowColumnedListViewSpecification",
      dataTransport: 2,
      itemsCount: length(items_data),
      columns: Enum.map(self.columns, &Column.as_dict/1),
      items: formatted_data
    }

    Logger.info("ColumnedList as_dict result: #{inspect(result)}")
    result
  end
end
