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
end
