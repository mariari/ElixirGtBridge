defmodule GtBridgeTest do
  use ExUnit.Case
  doctest GtBridge

  test "greets the world" do
    Examples.ETcp.start_tcp_connection()
  end

  test "Testing Serialization" do
    Examples.ESerialization.self_json()
    Examples.ESerialization.binary_json()
  end

  test "eval" do
    Examples.EEval.new_eval()
    Examples.EEval.new_eval_with_port()
    Examples.EEval.port_is_always_bound()
    Examples.EEval.bind_a_to_30()
    Examples.EEval.rebind_a_to_a()
  end

  test "completion" do
    Examples.ECompletion.complete_enum_dot()
    Examples.ECompletion.complete_alias()
    Examples.ECompletion.complete_erlang_module()
    Examples.ECompletion.complete_erlang_dot()
    Examples.ECompletion.complete_with_bindings()
    Examples.ECompletion.complete_struct()
    Examples.ECompletion.complete_empty_returns_something()
  end

  test "Testing Views" do
    Examples.EViews.int_list_view_ref()
    Examples.EViews.name_text_view_ref()
    Examples.EViews.empty_view()
    Examples.EViews.register_views()
    Examples.EViews.test_get_view_specs()
  end
end
