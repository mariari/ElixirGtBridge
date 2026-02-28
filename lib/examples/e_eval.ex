defmodule Examples.EEval do
  @moduledoc """
  I am examples for GtBridge.Eval, the evaluation GenServer.
  """

  use ExExample

  import ExUnit.Assertions

  alias GtBridge.Eval

  def rerun?(_), do: true

  @spec new_eval() :: pid()
  example new_eval do
    {:ok, pid} = DynamicSupervisor.start_child(EvaluationSupervisor, {Eval, []})

    assert Process.alive?(pid)

    pid
  end

  @spec new_eval_with_port(pos_integer()) :: pid()
  example new_eval_with_port(port \\ :rand.uniform(10000)) do
    {:ok, pid} = DynamicSupervisor.start_child(EvaluationSupervisor, {Eval, [port: port]})

    assert Process.alive?(pid)

    pid
  end

  @spec port_is_always_bound(pos_integer()) :: pid()
  example port_is_always_bound(port \\ :rand.uniform(10000)) do
    pid = new_eval_with_port(port)
    Eval.eval(pid, "port = 0.22", nil)

    assert Eval.eval(pid, "port", nil) == port

    pid
  end

  @spec bind_a_to_30() :: pid()
  example bind_a_to_30 do
    pid = new_eval()
    Eval.eval(pid, "a = 30", nil)

    assert Eval.eval(pid, "a", nil) == 30

    pid
  end

  example rebind_a_to_a do
    pid = bind_a_to_30()
    Eval.eval(pid, "a = :a", nil)

    assert Eval.eval(pid, "a", nil) == :a

    pid
  end
end
