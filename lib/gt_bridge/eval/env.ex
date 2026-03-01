defmodule GtBridge.Eval.Env do
  @moduledoc """
  I capture a Macro.Env with built-in helpers available.

  `Code.eval_string/3` accepts a `Macro.Env` as its third argument.
  By adding `h/1` to the env's functions list, every eval session
  can call `h(Enum)` without an explicit import.
  """

  @env __ENV__
       |> Macro.Env.prune_compile_info()
       |> Map.merge(%{
         module: nil,
         file: "nofile",
         line: 1,
         functions:
           [{GtBridge.Eval, [{:h, 1}]} | __ENV__.functions]
       })

  @spec env() :: Macro.Env.t()
  def env, do: @env
end
