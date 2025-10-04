defmodule GtBridge.Phlow.Empty do
  @moduledoc """
  An empty Phlow view specification.

  Used as a placeholder or to indicate no view should be shown.
  """
  use TypedStruct

  typedstruct do
    field(:view_title, String.t(), default: "Empty")
    field(:view_priority, integer(), default: 1)
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
  Convert the empty view to a dictionary format for serialization to GT.
  """
  @spec as_dict(t()) :: map()
  def as_dict(self) do
    %{
      title: self.view_title,
      priority: self.view_priority,
      viewName: "empty"
    }
  end
end
