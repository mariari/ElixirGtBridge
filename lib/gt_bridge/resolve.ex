defmodule GtBridge.Resolve do
  @spec data_type_to_string(any()) :: String.t()
  def data_type_to_string(obj) do
    IEx.Info.info(obj)
    |> Enum.find({"Data type", "Unknown"}, fn {x, _} -> "Data type" == x end)
    |> elem(1)
  end

  @spec data_type_to_module(any()) :: atom()
  def data_type_to_module(obj) do
    String.to_atom("Elixir." <> data_type_to_string(obj))
  end
end
