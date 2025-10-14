defmodule GtBridge.Phlow.View do
  @moduledoc """
  A Phlow view specification that wraps a specific view type (list, text, etc.)
  with common properties like title and priority.
  """
  use TypedStruct

  typedstruct do
    field(:title, String.t(), default: "Unknown")
    field(:priority, integer(), default: 1)
    field(:view_spec, any())
  end

  @doc """
  Convert the view to a dictionary format for serialization to GT.
  """
  @spec as_dict(t()) :: map()
  def as_dict(self) do
    view_dict = self.view_spec.as_dict()

    Map.merge(view_dict, %{
      title: self.title,
      priority: self.priority
    })
  end
end
