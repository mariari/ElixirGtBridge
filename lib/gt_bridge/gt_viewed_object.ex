defmodule GtBridge.GtViewedObject do
  @moduledoc """
  Helper module for getting view declarations for Elixir objects.

  This provides a way to get GT-compatible view specifications for
  any Elixir object, similar to Python's GtViewedObject.
  """

  alias GtBridge.Phlow.List
  alias GtBridge.Phlow.Text

  use GtBridge.View

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
        GtBridge.View.get_view_object(obj, views_server)

      _ ->
        # For primitive values, return default views
        get_default_views(object) ++
          GtBridge.View.get_view_specs(
            object,
            GtBridge.Resolve.data_type_to_module(object),
            views_server
          )
    end
  end

  # Get default views for primitive values that can't be gotten via
  # the macro
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

  defp get_default_views(_value) do
    []
  end

  defview get_default_view(<<self::binary>>, builder) do
    builder.text()
    |> Text.title("String")
    |> Text.priority(1)
    |> Text.string(self)
  end

  defview get_default_view(self = [_ | _], builder) do
    builder.list()
    |> List.priority(1)
    |> List.title("List")
    |> List.items(fn -> self end)
  end

  defview get_default_view(self = [], builder) do
    builder.list()
    |> List.priority(1)
    |> List.title("List")
    |> List.items(fn -> self end)
  end
end
