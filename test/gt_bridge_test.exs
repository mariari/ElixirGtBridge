defmodule GtBridgeTest do
  use ExUnit.Case
  doctest GtBridge

  test "greets the world" do
    Examples.ETcp.start_tcp_connection()
  end
end
