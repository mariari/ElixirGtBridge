defmodule Examples.ESerialization do
  import ExUnit.Assertions

  @spec self_json() :: binary()
  def self_json() do
    assert {:ok, res} = GtBridge.Serializer.to_json(self())

    assert {:ok, self()} == GtBridge.Serializer.from_json(res)

    res
  end
end
