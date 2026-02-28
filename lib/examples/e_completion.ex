defmodule Examples.ECompletion do
  import ExUnit.Assertions

  alias GtBridge.Completion

  @spec complete_enum_dot() :: [String.t()]
  def complete_enum_dot() do
    results = Completion.complete("Enum.ma")

    assert "Enum.map" in results
    assert "Enum.map_every" in results

    results
  end

  @spec complete_alias() :: [String.t()]
  def complete_alias() do
    results = Completion.complete("GenSer")

    assert "GenServer" in results

    results
  end

  @spec complete_erlang_module() :: [String.t()]
  def complete_erlang_module() do
    results = Completion.complete(":erlan")

    assert ":erlang" in results

    results
  end

  @spec complete_erlang_dot() :: [String.t()]
  def complete_erlang_dot() do
    results = Completion.complete(":erlang.no")

    assert ":erlang.node" in results

    results
  end

  @spec complete_with_bindings() :: [String.t()]
  def complete_with_bindings() do
    results = Completion.complete("my_v", my_var: 42, my_val: "hello")

    assert "my_var" in results
    assert "my_val" in results

    results
  end

  @spec complete_struct() :: [String.t()]
  def complete_struct() do
    results = Completion.complete("%MapS")

    assert "MapSet" in results

    results
  end

  @spec complete_empty_returns_something() :: [String.t()]
  def complete_empty_returns_something() do
    results = Completion.complete("is_")

    assert length(results) > 0

    results
  end
end
