defmodule GtBridgeTest do
  use ExUnit.Case
  doctest GtBridge

  test "greets the world" do
    assert GtBridge.hello() == :world
  end
end
