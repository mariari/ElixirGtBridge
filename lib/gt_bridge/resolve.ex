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

  @doc """
  I return {start_line, end_line} for a function definition in a module's source.
  Returns nil if the function or source file cannot be found.
  """
  @spec function_lines(GtBridge.Documentation.t() | module(), atom(), non_neg_integer()) ::
          {pos_integer(), pos_integer()} | nil
  def function_lines(%GtBridge.Documentation{query: {:function, module, name, arity}}) do
    function_lines(module, name, arity)
  end

  def function_lines(module) when is_atom(module), do: nil
  def function_lines(%{__struct__: _}), do: nil
  def function_lines(_), do: nil

  def function_lines(module, name, arity) do
    with path when is_binary(path) <- source_file(module),
         {:ok, source} <- File.read(path),
         {:ok, ast} <-
           Code.string_to_quoted(source,
             columns: true,
             token_metadata: true
           ) do
      find_function_lines(ast, name, arity)
    else
      _ -> nil
    end
  end

  defp find_function_lines({:defmodule, _, [_, [do: {:__block__, _, body}]]}, name, arity) do
    matches =
      body
      |> Enum.filter(fn
        {kind, _, _} when kind in [:def, :defp] -> true
        _ -> false
      end)
      |> Enum.filter(fn {_kind, _meta, [head | _]} ->
        {fn_name, fn_arity} = function_head_name_arity(head)
        fn_name == name and fn_arity == arity
      end)

    case matches do
      [] ->
        nil

      clauses ->
        first_meta = clauses |> List.first() |> elem(1)
        last_meta = clauses |> List.last() |> elem(1)
        start_line = first_meta[:line]

        end_line =
          get_in(last_meta, [:end, :line]) ||
            get_in(last_meta, [:end_of_expression, :line]) ||
            last_meta[:line]

        {start_line, end_line}
    end
  end

  defp find_function_lines(_, _, _), do: nil

  defp function_head_name_arity({:when, _, [head | _]}),
    do: function_head_name_arity(head)

  defp function_head_name_arity({name, _, args}) when is_list(args),
    do: {name, length(args)}

  defp function_head_name_arity({name, _, _}),
    do: {name, 0}

  defp compile_source(module) do
    with true <- Code.ensure_loaded?(module),
         path when is_list(path) <- module.__info__(:compile)[:source] do
      List.to_string(path)
    else
      _ -> nil
    end
  end
end
