defmodule GtBridge.MacroInspector do
  defp pass(ast, env), do: Macro.prewalk(ast, &Macro.expand_once(&1, env))
  defp code(ast), do: Code.format_string!(Macro.to_string(ast))

  defp steps(ast, env \\ __ENV__, limit \\ 50) do
    do_steps(ast, env, [code(ast)], limit)
  end

  defp do_steps(ast, env, acc, 0), do: Enum.reverse([:limit | acc])
  defp do_steps(ast, env, acc, n) do
    next = pass(ast, env)
    if next == ast, do: Enum.reverse(acc),
      else: do_steps(next, env, [code(next) | acc], n - 1)
  end

  def inspect(ast) do
    steps(ast)
  end
end
