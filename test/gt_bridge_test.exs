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

  test "Testing Views" do
    Examples.EViews.some_view_ref()
    Examples.EViews.empty_view()
    Examples.EViews.add_some_view()
    Examples.EViews.delete_some_view()
  end
end
