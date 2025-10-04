defmodule GtBridge.GtViewedObject do
  @moduledoc """
  Helper module for getting view declarations for Elixir objects.

  This provides a way to get GT-compatible view specifications for
  any Elixir object, similar to Python's GtViewedObject.
  """

  @doc """
  Get view declarations for an object by its registry ID.
  This is called from GT via eval when inspecting a proxy object.
  """
  @spec get_views_declarations_by_id(non_neg_integer()) :: list(map())
  def get_views_declarations_by_id(object_id) do
    case GtBridge.ObjectRegistry.get(object_id) do
      {:ok, object} ->
        get_views_declarations(object)

      :error ->
        # Object not found in registry
        []
    end
  end

  @doc """
  Get view declarations for any object.
  This can be called from GT via eval.
  """
  @spec get_views_declarations(any(), GenServer.server()) :: list(map())
  def get_views_declarations(object, views_server \\ GtBridge.Views) do
    case object do
      %{__struct__: _} = obj ->
        # Get views for structured data
        GtBridge.View.get_view_specs(obj, views_server)

      _ ->
        # For primitive values, return default views
        get_default_views(object)
    end
  end

  # Get default views for primitive values.
  defp get_default_views(value) when is_integer(value) do
    [
      %{
        title: "Integer",
        priority: 1,
        viewName: "GtPhlowTextEditorViewSpecification",
        dataTransport: 2,
        string: Integer.to_string(value)
      }
    ]
  end

  defp get_default_views(value) when is_binary(value) do
    [
      %{
        title: "String",
        priority: 1,
        viewName: "GtPhlowTextEditorViewSpecification",
        dataTransport: 2,
        string: value
      }
    ]
  end

  defp get_default_views(value) when is_list(value) do
    [
      %{
        title: "List",
        priority: 1,
        viewName: "GtPhlowListViewSpecification",
        dataTransport: 2,
        itemsCount: length(value),
        items: value
      }
    ]
  end

  defp get_default_views(_value) do
    []
  end
end
