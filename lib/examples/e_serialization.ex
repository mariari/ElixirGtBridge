defmodule Examples.ESerialization do
  import ExUnit.Assertions

  @spec self_json() :: binary()
  def self_json() do
    assert {:ok, res} = GtBridge.Serializer.to_json(self())

    assert {:ok, self()} == GtBridge.Serializer.from_json(res)

    res
  end

  @spec binary_json() :: binary()
  def binary_json() do
    assert {:ok, res} = GtBridge.Serializer.to_json(<<222, 50, 60>>)
    assert res == "[\"__base64__\",\"3jI8\"]"
    assert {:ok, <<222, 50, 60>>} == GtBridge.Serializer.from_json(res)
    res
  end
end
