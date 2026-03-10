defmodule GtBridge.Resolve do
  @spec data_type_to_string(any()) :: String.t()
  def data_type_to_string(obj) do
    IEx.Info.info(obj)
    |> Enum.find({"Data type", "Unknown"}, fn {x, _} -> "Data type" == x end)
    |> elem(1)
  end

  @spec data_type_to_module(any()) :: atom()
  def data_type_to_module(obj) do
    String.to_atom("Elixir." <> data_type_to_string(obj))
  end

  @doc """
  I return the source file path for an object, or nil if unavailable.
  """
  @spec source_file(any()) :: String.t() | nil
  def source_file(%GtBridge.Documentation{query: {_, module}}) do
    compile_source(module)
  end

  def source_file(%GtBridge.Documentation{query: {_, module, _, _}}) do
    compile_source(module)
  end

  def source_file(%GtBridge.Documentation{query: {_, module, _}}) do
    compile_source(module)
  end

  def source_file(%{__struct__: module}) do
    compile_source(module)
  end

  def source_file(module) when is_atom(module) do
    compile_source(module)
  end

  def source_file(_), do: nil

  defp compile_source(module) do
    with true <- Code.ensure_loaded?(module),
         path when is_list(path) <- module.__info__(:compile)[:source] do
      List.to_string(path)
    else
      _ -> nil
    end
  end
end
