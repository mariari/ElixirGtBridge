defmodule GtBridge.Phlow.List do
  @moduledoc """
  A Phlow list view specification.

  List views display collections of items in GT's inspector.
  """
  use TypedStruct

  typedstruct do
    field(:view_title, String.t(), default: "Unknown")
    field(:view_priority, integer(), default: 1)
    field(:items_callback, (-> list()) | nil, default: nil)
    field(:item_format, (any() -> String.t()) | nil, default: nil)
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
  Set the format function for displaying items.
  """
  @spec item_format(t(), (any() -> String.t())) :: t()
  def item_format(self, format_fn) do
    %__MODULE__{self | item_format: format_fn}
  end

  @doc """
  Convert the list view to a dictionary format for serialization to GT.
  """
  @spec as_dict(t()) :: map()
  def as_dict(self) do
    items_data =
      if self.items_callback do
        self.items_callback.()
      else
        []
      end

    %{
      title: self.view_title,
      priority: self.view_priority,
      viewName: "GtPhlowListViewSpecification",
      dataTransport: 2,
      itemsCount: length(items_data),
      items: items_data
    }
  end
end
