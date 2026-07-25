defmodule Examples.EInterfaces do
  @moduledoc """
  I am examples for GtBridge.Analysis.Interfaces, the behaviour and
  protocol listing.
  """

  use ExExample

  import ExUnit.Assertions

  alias GtBridge.Analysis.Interfaces

  @spec behaviour_with_implementors() :: map()
  example behaviour_with_implementors do
    gen_server = Interfaces.in_app(:elixir) |> Enum.find(&(&1.name == "GenServer"))

    assert gen_server.kind == :behaviour
    assert Enum.any?(gen_server.callbacks, &String.starts_with?(&1, "@callback handle_call"))
    assert "handle_call/3" in gen_server.callback_names

    eval = Enum.find(gen_server.implementors, &(&1.module == "GtBridge.Eval"))
    assert "handle_call/3" in eval.implements
    assert String.ends_with?(eval.source, "lib/gt_bridge/eval.ex")

    gen_server
  end

  @spec protocol_with_impls() :: map()
  example protocol_with_impls do
    enumerable = Interfaces.in_app(:elixir) |> Enum.find(&(&1.name == "Enumerable"))

    assert enumerable.kind == :protocol
    assert "count/1" in enumerable.functions

    list = Enum.find(enumerable.impls, &(&1.for == "List"))
    assert list.module == "Enumerable.List"

    enumerable
  end

  @spec module_interface_facts() :: map()
  example module_interface_facts do
    facts = Interfaces.of_module(GtBridge.Eval)

    assert facts.defines == nil
    gen_server = Enum.find(facts.implements, &(&1.name == "GenServer"))
    assert "handle_call/3" in gen_server.implements

    behaviour = Interfaces.of_module(GenServer)
    assert behaviour.defines.kind == :behaviour
    assert Enum.any?(behaviour.defines.implementors, &(&1.module == "GtBridge.Eval"))

    Code.ensure_loaded(Enumerable.List)
    list = Interfaces.of_module(List)
    assert Enum.any?(list.implements, &(&1.name == "Enumerable"))

    facts
  end
end
