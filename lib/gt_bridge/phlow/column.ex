defmodule GtBridge.Phlow.Column do
  @moduledoc """
  A column definition for columned list and tree views.
  """
  use TypedStruct

  typedstruct do
    field(:title, String.t(), default: "Column")
    field(:format, (any() -> String.t()) | nil, default: nil)
    field(:width, integer() | nil, default: nil)
  end

  @doc """
  Create a new column with a title.
  """
  @spec new(String.t()) :: t()
  def new(title) do
    %__MODULE__{title: title}
  end

  @doc """
  Set the format function for the column.
  """
  @spec format(t(), (any() -> String.t())) :: t()
  def format(self, format_fn) do
    %__MODULE__{self | format: format_fn}
  end

  @doc """
  Set the width of the column.
  """
  @spec width(t(), integer()) :: t()
  def width(self, width_value) do
    %__MODULE__{self | width: width_value}
  end

  @doc """
  Convert the column to a dictionary for serialization.
  """
  @spec as_dict(t()) :: map()
  def as_dict(self) do
    base = %{
      title: self.title
    }

    base = if self.width, do: Map.put(base, :width, self.width), else: base
    base
  end

  @doc """
  Format an item using the column's format function.
  """
  @spec format_item(t(), any()) :: String.t()
  def format_item(self, item) do
    if self.format do
      self.format.(item)
    else
      to_string(item)
    end
  end
end
