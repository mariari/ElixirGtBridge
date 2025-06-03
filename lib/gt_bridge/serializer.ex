# We make this a module as jexon is as well, simple enough
defmodule GtBridge.Serializer do
  @spec to_json(data :: any()) :: {:ok, json :: String.t()}
  def to_json(data) do
    to_json(data, [])
  end

  @spec to_json(data :: any(), opts :: keyword()) :: {:ok, json :: String.t()}
  def to_json(data, options) when is_pid(data) do
    Jexon.to_json(["__pid__" | :erlang.pid_to_list(data)], options)
  end

  def to_json(data, options) do
    Jexon.to_json(data, options)
  end

  @spec from_json(json :: String.t()) :: {:ok, any()} | {:error, Jason.DecodeError.t()}
  def from_json(data) do
    from_json(data, [])
  end

  @spec from_json(json :: String.t(), opts :: keyword()) ::
          {:ok, any()} | {:error, Jason.DecodeError.t()}
  def from_json(data, options) do
    case Jexon.from_json(data, options) do
      {:ok, ["__pid__" | rest]} -> {:ok, :erlang.list_to_pid(rest)}
      x -> x
    end
  end
end
