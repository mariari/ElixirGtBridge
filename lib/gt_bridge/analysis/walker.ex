defmodule GtBridge.Analysis.Walker do
  @moduledoc """
  I walk Elixir AST and extract call sites.

  I am the AST-walking subsystem of `GtBridge.Analysis`: given a
  parsed quoted form I collect remote and local call entries, and
  given source text I extract the alias map needed to resolve them
  to fully qualified module names.

  ### Public API

  - `collect_calls/2` — walk an AST and return raw call entries
  - `extract_alias_map/1` — parse `alias` directives from source
  - `resolve_call_aliases/2` — rewrite call entries through an alias map
  """

  @type call_entry :: %{
          target_module: String.t(),
          function: String.t(),
          arity: non_neg_integer(),
          line: pos_integer() | nil,
          column: pos_integer() | nil
        }

  @doc """
  I walk `ast` and return raw call entries.

  When `context_module` is non-nil, local calls inside that module
  are emitted with `:target_module` set to the module's inspect form;
  otherwise only remote calls are emitted.
  """
  @spec collect_calls(Macro.t(), module() | nil) :: [call_entry()]
  def collect_calls(ast, context_module \\ nil) do
    ctx_str = if context_module, do: inspect(context_module)
    walk_calls(ast, [], ctx_str)
  end

  @doc """
  I parse `alias` directives from `source` and return a map from
  the short name to the fully qualified module string.
  """
  @spec extract_alias_map(String.t()) :: %{String.t() => String.t()}
  def extract_alias_map(source) do
    source
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      trimmed = String.trim(line)

      cond do
        match = Regex.run(~r/^alias\s+(\S+),\s*as:\s*(\w+)/, trimmed) ->
          [{Enum.at(match, 2), Enum.at(match, 1)}]

        match = Regex.run(~r/^alias\s+([\w.]+)$/, trimmed) ->
          full = Enum.at(match, 1)
          short = full |> String.split(".") |> List.last()
          [{short, full}]

        true ->
          []
      end
    end)
    |> Map.new()
  end

  @doc """
  I rewrite each call entry's `:target_module` through `aliases` and
  return the list sorted by `{line, column}`.
  """
  @spec resolve_call_aliases([call_entry()], %{String.t() => String.t()}) :: [call_entry()]
  def resolve_call_aliases(calls, aliases) do
    calls
    |> Enum.map(fn call ->
      first = call.target_module |> String.split(".") |> List.first()

      case Map.get(aliases, first) do
        nil ->
          call

        full ->
          rest = call.target_module |> String.split(".") |> Enum.drop(1)
          resolved = [full | rest] |> Enum.join(".")
          %{call | target_module: resolved}
      end
    end)
    |> Enum.sort_by(&{&1.line, &1.column})
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  # `a |> M.f(b)` parses as {:|>, _, [a, M.f(b)]} but means M.f(a, b),
  # so the right-hand call gets arity length(args) + 1. Walk the left
  # side normally and the right side as a pipe target.
  defp walk_calls({:|>, _, [left, right]}, acc, ctx) do
    walk_pipe_target(right, walk_calls(left, acc, ctx), ctx)
  end

  # Function-reference syntax: `M.f/arity` parses as `M.f() / arity`
  # (zero-arg call divided by an integer).  Without this clause we
  # would emit M.f/0 and lose the arity, so e.g. h(Mod.handle_call/3)
  # would expand the wrong function.  Match the / outer node, emit
  # with the explicit arity, and don't recurse into the inner call.
  defp walk_calls(
         {:/, _, [{{:., _, [{:__aliases__, _, parts}, fun]}, meta, []}, arity]},
         acc,
         _ctx
       )
       when is_atom(fun) and is_integer(arity) do
    [remote_entry(parts, fun, arity, meta) | acc]
  end

  defp walk_calls({:/, _, [{fun, meta, []}, arity]}, acc, ctx)
       when is_atom(fun) and is_integer(arity) and is_binary(ctx) do
    [local_entry(ctx, fun, arity, meta) | acc]
  end

  defp walk_calls(
         {{:., _, [{:__aliases__, _, parts}, fun]}, meta, args},
         acc,
         ctx
       )
       when is_atom(fun) and is_list(args) do
    acc = [remote_entry(parts, fun, length(args), meta) | acc]
    Enum.reduce(args, acc, fn n, a -> walk_calls(n, a, ctx) end)
  end

  # Local call: `foo(args)` where the function is defined in the current
  # module.  Only emitted when ctx is a string (i.e. we have a context
  # module).  Bogus matches (operators, special forms, kernel macros) are
  # filtered out by call_sites/2's defined_function_names check.
  defp walk_calls({fun, meta, args}, acc, ctx)
       when is_atom(fun) and is_list(args) and is_binary(ctx) do
    acc = [local_entry(ctx, fun, length(args), meta) | acc]
    Enum.reduce(args, acc, fn n, a -> walk_calls(n, a, ctx) end)
  end

  defp walk_calls({_, _, args}, acc, ctx) when is_list(args),
    do: Enum.reduce(args, acc, fn n, a -> walk_calls(n, a, ctx) end)

  defp walk_calls({a, b}, acc, ctx), do: walk_calls(b, walk_calls(a, acc, ctx), ctx)

  defp walk_calls(items, acc, ctx) when is_list(items),
    do: Enum.reduce(items, acc, fn n, a -> walk_calls(n, a, ctx) end)

  defp walk_calls(_, acc, _), do: acc

  defp walk_pipe_target(
         {{:., _, [{:__aliases__, _, parts}, fun]}, meta, args},
         acc,
         ctx
       )
       when is_atom(fun) and is_list(args) do
    acc = [remote_entry(parts, fun, length(args) + 1, meta) | acc]
    Enum.reduce(args, acc, fn n, a -> walk_calls(n, a, ctx) end)
  end

  defp walk_pipe_target({fun, meta, args}, acc, ctx)
       when is_atom(fun) and is_list(args) and is_binary(ctx) do
    acc = [local_entry(ctx, fun, length(args) + 1, meta) | acc]
    Enum.reduce(args, acc, fn n, a -> walk_calls(n, a, ctx) end)
  end

  defp walk_pipe_target(node, acc, ctx), do: walk_calls(node, acc, ctx)

  defp remote_entry(parts, fun, arity, meta) do
    %{
      target_module: parts |> Enum.map_join(".", &Atom.to_string/1),
      function: Atom.to_string(fun),
      arity: arity,
      line: meta[:line],
      column: meta[:column]
    }
  end

  defp local_entry(ctx_str, fun, arity, meta) do
    %{
      target_module: ctx_str,
      function: Atom.to_string(fun),
      arity: arity,
      line: meta[:line],
      column: meta[:column]
    }
  end
end
