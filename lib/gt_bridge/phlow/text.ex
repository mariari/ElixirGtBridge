defmodule GtBridge.Phlow.Text do
  @moduledoc """
  A Phlow text editor view specification.

  Text views display textual content in GT's inspector.
  """
  use TypedStruct

  typedstruct do
    field(:view_title, String.t(), default: "Unknown")
    field(:view_priority, integer(), default: 1)
    field(:text_string, String.t(), default: "")
  end

  @doc """
  Set the title of the view.
  """
  @spec title(t(), String.t()) :: t()
  def title(self, title_text) do
    %__MODULE__{self | view_title: title_text}
  end

  @spec priority(t(), integer()) :: t()
  def priority(self, priority_value) do
    %__MODULE__{self | view_priority: priority_value}
  end

  @doc """
  Set the text content to display.
  """
  @spec string(t(), String.t() | (() -> String.t())) :: t()
  def string(self, text) when is_binary(text) do
    %__MODULE__{self | text_string: text}
  end

  def string(self, text_fn) when is_function(text_fn, 0) do
    %__MODULE__{self | text_string: text_fn.()}
  end

  @doc """
  Convert the text view to a dictionary format for serialization to GT.
  """
  @spec as_dict(t()) :: map()
  def as_dict(self) do
    %{
      title: self.view_title,
      priority: self.view_priority,
      viewName: "GtPhlowTextEditorViewSpecification",
      dataTransport: 2,
      string: self.text_string
    }
  end
end
