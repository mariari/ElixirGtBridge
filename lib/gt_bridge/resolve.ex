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
  def source_file(obj), do: obj |> extract_module() |> compile_source()

  defp extract_module(%GtBridge.Documentation{query: query}), do: elem(query, 1)
  defp extract_module(%{__struct__: module}), do: module
  defp extract_module(module) when is_atom(module), do: module
  defp extract_module(_), do: nil

  @doc """
  I return {start_line, end_line} for a function definition in a module's source.
  Delegates to `GtBridge.Analysis.all_functions/1` to avoid duplicating AST logic.
  """
  @spec function_lines(GtBridge.Documentation.t()) :: {pos_integer(), pos_integer()} | nil
  def function_lines(%GtBridge.Documentation{query: {:function, module, name, arity}}) do
    function_lines(module, name, arity)
  end

  def function_lines(_), do: nil

  @spec function_lines(module(), atom(), non_neg_integer()) ::
          {pos_integer(), pos_integer()} | nil
  def function_lines(module, name, arity) do
    name_str = Atom.to_string(name)

    case GtBridge.Analysis.all_functions(module) do
      funs when is_list(funs) ->
        case Enum.find(funs, &(&1.name == name_str and &1.arity == arity)) do
          nil -> nil
          f -> {f.start, f.end_line}
        end

      _ ->
        nil
    end
  end

  defp compile_source(nil), do: nil

  defp compile_source(module) do
    with true <- Code.ensure_loaded?(module),
         path when is_list(path) <- module.__info__(:compile)[:source] do
      List.to_string(path)
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
