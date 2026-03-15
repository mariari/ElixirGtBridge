defmodule GtBridge.Eval.Env do
  @moduledoc """
  I capture a Macro.Env with built-in helpers available.

  `Code.eval_quoted_with_env/3` accepts a `Macro.Env`. By adding
  `h/1` to the macros list and `flush/0` to the functions list,
  every eval session can call them without an explicit import.
  """

  @env __ENV__
       |> Macro.Env.prune_compile_info()
       |> Map.merge(%{
         module: nil,
         file: "nofile",
         line: 1,
         functions:
           [{GtBridge.Eval, [{:flush, 0}]} | __ENV__.functions],
         macros:
           [{GtBridge.Eval, [{:h, 1}]} | __ENV__.macros]
       })

  @spec env() :: Macro.Env.t()
  def env, do: @env
end
