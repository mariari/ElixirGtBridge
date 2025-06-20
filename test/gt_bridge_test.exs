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

  test "Testing Views" do
    Examples.EViews.some_view_ref()
    Examples.EViews.empty_view()
    Examples.EViews.add_some_view()
    Examples.EViews.delete_some_view()
  end
end
