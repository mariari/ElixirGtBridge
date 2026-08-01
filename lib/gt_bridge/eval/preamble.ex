defmodule GtBridge.Eval.Preamble do
  @moduledoc """
  I prime an evaluation session with a module's preamble (alias /
  import / require declarations) so completion + eval work in the
  module's namespace context.

  GT-side editor coders call `editor_session/2` once on open;
  subsequent completion + eval requests in that session see the
  same env state.
  """

  @doc """
  I create or return an eval session with a module's preamble loaded.

  Evals the source file's alias/import/require statements into the
  session's env, so completion works in context. Returns the session ID.
  """
  @spec editor_session(module(), String.t()) :: String.t()
  def editor_session(mod, sid) do
    # Create the session if it doesn't exist — safe for module
    # coder sessions which use synchronous eval (no port needed)
    pid = GtBridge.EvalRegistry.get_or_create(sid)
    load_imports(mod, pid)
    sid
  end

  @doc """
  I return the alias/import/require directives from a module's source,
  each re-rendered on a single line. GT's snippet wrap prepends these
  verbatim, so they must parse alone no matter how the source wrapped
  them ("use" is excluded — it needs a module context to expand).
  """
  @spec directives(module()) :: [String.t()]
  def directives(mod) when is_atom(mod) do
    GtBridge.Resolve.with_source(mod, [], fn source ->
      Enum.map(directive_nodes(source, mod), &one_line/1)
    end)
  end

  # token_metadata remembers the source's own line breaks and
  # Macro.to_string honors them; drop :newlines so each directive
  # renders on one line no matter how the file wrapped it.
  defp one_line(node) do
    node
    |> Macro.prewalk(fn
      {f, meta, args} when is_list(meta) -> {f, Keyword.drop(meta, [:newlines]), args}
      other -> other
    end)
    |> Macro.to_string()
  end

  defp directive_nodes(source, mod) do
    case GtBridge.Analysis.Source.quoted(source) do
      {:ok, ast} -> GtBridge.Analysis.Source.directives(ast, inspect(mod))
      _ -> []
    end
  end

  defp load_imports(mod, pid) do
    state = :sys.get_state(pid)

    base_env = eval_into_env(quote(do: import(unquote(mod))), state.env)

    new_env =
      GtBridge.Resolve.with_source(mod, base_env, fn source ->
        Enum.reduce(directive_nodes(source, mod), base_env, &eval_into_env/2)
      end)

    :sys.replace_state(pid, fn s ->
      %{s | env: new_env, locals: private_functions(mod)}
    end)
  end

  # import only brings publics into the env; the session records the
  # defps separately so completion can offer them too.
  defp private_functions(mod) do
    exports = mod.module_info(:exports)

    for {name, arity} <- mod.module_info(:functions),
        {name, arity} not in exports,
        str = Atom.to_string(name),
        not String.starts_with?(str, "-") do
      case str do
        # defmacrop compiles to MACRO-name with an extra env argument
        "MACRO-" <> macro -> {String.to_atom(macro), arity - 1}
        _ -> {name, arity}
      end
    end
  rescue
    _ -> []
  end

  defp eval_into_env(quoted, env) do
    # Suppress compiler diagnostics (e.g. Ecto's __meta__ warnings)
    # during preamble eval — they're harmless but noisy in the terminal
    old = Code.get_compiler_option(:no_warn_undefined)
    Code.put_compiler_option(:no_warn_undefined, :all)

    try do
      {_, _, new_env} = Code.eval_quoted_with_env(quoted, [], env)
      new_env
    rescue
      e in [CompileError, UndefinedFunctionError, ArgumentError] ->
        _ = e
        env
    after
      Code.put_compiler_option(:no_warn_undefined, old)
    end
  end
end
