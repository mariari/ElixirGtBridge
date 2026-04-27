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
  - `extract_import_map/1` — parse `import` directives from source
  - `resolve_call_aliases/2` — rewrite call entries through an alias map
  - `resolve_import_targets/2` — rewrite local entries through an import map
  """

  @type call_entry :: %{
          target_module: String.t(),
          function: String.t(),
          arity: non_neg_integer(),
          line: pos_integer() | nil,
          column: pos_integer() | nil,
          local: boolean()
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

        match = Regex.run(~r/^alias\s+([\w.]+)\.\{([^}]+)\}/, trimmed) ->
          prefix = Enum.at(match, 1)

          Enum.at(match, 2)
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(fn name -> {name, "#{prefix}.#{name}"} end)

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
  I parse `import` directives from `source` and return a map from
  `{function_name, arity}` to the full module string.

  Three forms recognized at the module level:
    import Foo                          all exported funs from Foo
    import Foo, only: [bar: 1, baz: 2]  whitelist
    import Foo.{A, B}                   all funs from each

  Imports nested inside `def`/`defp` are scoped to that function and
  intentionally NOT collected here — module-level imports cover the
  common case.  `import Foo, except: [...]` and `:functions`/`:macros`
  shorthands are treated as full imports of the module's exports.
  """
  @spec extract_import_map(String.t()) :: %{{String.t(), non_neg_integer()} => String.t()}
  def extract_import_map(source) do
    source
    |> String.split("\n")
    |> Enum.flat_map(&parse_import_line/1)
    |> Map.new()
  end

  @doc """
  I rewrite local entries (`call.local == true`) whose
  `{function, arity}` is in `imports`, setting `:target_module` to
  the imported module and clearing `:local`.  Remote entries pass
  through unchanged.
  """
  @spec resolve_import_targets([call_entry()], %{{String.t(), non_neg_integer()} => String.t()}) ::
          [call_entry()]
  def resolve_import_targets(calls, imports) do
    Enum.map(calls, fn call ->
      if Map.get(call, :local, false) do
        case Map.get(imports, {call.function, call.arity}) do
          nil -> call
          module -> %{call | target_module: module, local: false}
        end
      else
        call
      end
    end)
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
      column: meta[:column],
      local: false
    }
  end

  defp local_entry(ctx_str, fun, arity, meta) do
    %{
      target_module: ctx_str,
      function: Atom.to_string(fun),
      arity: arity,
      line: meta[:line],
      column: meta[:column],
      local: true
    }
  end

  defp parse_import_line(line) do
    trimmed = String.trim(line)

    cond do
      # import Foo, only: [bar: 1, baz: 2]
      match = Regex.run(~r/^import\s+([\w.]+),\s*only:\s*\[([^\]]+)\]/, trimmed) ->
        mod_str = Enum.at(match, 1)

        Enum.at(match, 2)
        |> parse_only_list()
        |> Enum.map(fn {name, arity} -> {{name, arity}, mod_str} end)

      # import Foo.{A, B}
      match = Regex.run(~r/^import\s+([\w.]+)\.\{([^}]+)\}/, trimmed) ->
        prefix = Enum.at(match, 1)

        Enum.at(match, 2)
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.flat_map(fn name ->
          full_str = "#{prefix}.#{name}"

          for {fn_name, arity} <- exports_of(full_str) do
            {{fn_name, arity}, full_str}
          end
        end)

      # import Foo (catches `import Foo, except:`, `import Foo, only: :functions`, etc.)
      match = Regex.run(~r/^import\s+([\w.]+)/, trimmed) ->
        mod_str = Enum.at(match, 1)

        for {fn_name, arity} <- exports_of(mod_str) do
          {{fn_name, arity}, mod_str}
        end

      true ->
        []
    end
  end

  defp parse_only_list(str) do
    str
    |> String.split(",")
    |> Enum.flat_map(fn entry ->
      case Regex.run(~r/^\s*(\w+):\s*(\d+)\s*$/, entry) do
        [_, name, arity] -> [{name, String.to_integer(arity)}]
        _ -> []
      end
    end)
  end

  defp exports_of(mod_str) do
    mod = Module.concat([mod_str])

    if Code.ensure_loaded?(mod) do
      mod.module_info(:exports)
      |> Enum.reject(fn {name, _} -> name in [:__info__, :module_info] end)
      |> Enum.map(fn {name, arity} -> {Atom.to_string(name), arity} end)
    else
      []
    end
  rescue
    _ -> []
  end
end
