defmodule Examples.ESerialization do
  use ExExample

  import ExUnit.Assertions

  def rerun?(_), do: true

  @spec self_json() :: binary()
  example self_json do
    assert {:ok, res} = GtBridge.Serializer.to_json(self())

    assert {:ok, self()} == GtBridge.Serializer.from_json(res)

    res
  end

  @spec binary_json() :: binary()
  example binary_json do
    assert {:ok, res} = GtBridge.Serializer.to_json(<<222, 50, 60>>)
    assert res == "[\"__base64__\",\"3jI8\"]"
    assert {:ok, <<222, 50, 60>>} == GtBridge.Serializer.from_json(res)
    res
  end
end
