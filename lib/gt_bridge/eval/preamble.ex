defmodule GtBridge.Eval.Preamble do
  @moduledoc """
  I prime an evaluation session with a module's preamble (alias /
  import / require declarations) so completion + eval work in the
  module's namespace context.

  GT-side editor coders call `editor_session/2` once on open;
  subsequent completion + eval requests in that session see the
  same env state.
  """

  # Skip "use " — it requires a module context and crashes in
  # eval env (e.g. "use TypedStruct" triggers __meta__ errors)
  @preamble_starts ["import ", "alias ", "require "]

  @doc """
  I create or return an eval session with a module's preamble loaded.

  Walks the source file's use/import/alias/require lines and evals
  them into the session's env, so completion works in context.
  Returns the session ID.
  """
  @spec editor_session(module(), String.t()) :: String.t()
  def editor_session(mod, sid) do
    # Create the session if it doesn't exist — safe for module
    # coder sessions which use synchronous eval (no port needed)
    pid = GtBridge.EvalRegistry.get_or_create(sid)
    load_imports(mod, pid)
    sid
  end

  @doc "I return the alias/import/require lines from a module's source."
  @spec directives(module()) :: [String.t()]
  def directives(mod) when is_atom(mod) do
    GtBridge.Resolve.with_source(mod, [], &directives/1)
  end

  def directives(source) when is_binary(source) do
    source
    |> String.split("\n")
    |> Stream.map(&String.trim/1)
    |> Stream.take_while(fn line ->
      not (String.starts_with?(line, "def ") or String.starts_with?(line, "defp "))
    end)
    |> Enum.filter(fn line ->
      Enum.any?(@preamble_starts, &String.starts_with?(line, &1))
    end)
  end

  defp load_imports(mod, pid) do
    state = :sys.get_state(pid)

    base_env = eval_into_env("import #{inspect(mod)}", state.env)

    new_env =
      GtBridge.Resolve.with_source(mod, base_env, fn source ->
        source
        |> directives()
        |> Enum.reduce(base_env, &eval_into_env/2)
      end)

    :sys.replace_state(pid, fn s -> %{s | env: new_env} end)
  end

  defp eval_into_env(line, env) do
    # Suppress compiler diagnostics (e.g. Ecto's __meta__ warnings)
    # during preamble eval — they're harmless but noisy in the terminal
    old = Code.get_compiler_option(:no_warn_undefined)
    Code.put_compiler_option(:no_warn_undefined, :all)

    try do
      {_, _, new_env} = Code.eval_quoted_with_env(Code.string_to_quoted!(line), [], env)
      new_env
    rescue
      e in [CompileError, SyntaxError, TokenMissingError, UndefinedFunctionError, ArgumentError] ->
        _ = e
        env
    after
      Code.put_compiler_option(:no_warn_undefined, old)
    end
  end

end
