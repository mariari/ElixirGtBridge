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

  @doc """
  I read `mod`'s source file once and pass the contents to `fun`,
  returning whatever `fun` returns.  When the module has no source
  file or the file can't be read I return `default` -- macro-only
  modules, BEAM-only deps, etc. fall through cleanly without
  raising.

  Every analysis pass that walks a module's text (function
  extraction, alias map, eval preamble, editor session) routes
  through me so the source-resolution + read + fallback shape
  lives in one place.
  """
  @spec with_source(module(), default, (String.t() -> default | result)) :: default | result
        when default: any(), result: any()
  def with_source(mod, default, fun) do
    with path when is_binary(path) <- source_file(mod),
         {:ok, source} <- File.read(path) do
      fun.(source)
    else
      _ -> default
    end
  end

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
          # Macro-generated entries have start: 0 / end_line: 0 — no
          # actual line range to scroll to.  Returning {0, 0} would
          # have GT match every start: 0 entry (all of them, alphabetically
          # first wins) instead of nothing.
          %{start: 0} -> nil
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
    _ in [UndefinedFunctionError, ArgumentError, FunctionClauseError] -> nil
  end
end
