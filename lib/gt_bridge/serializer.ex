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

  def to_json(data, options) when is_binary(data) do
    case Jexon.to_json(data, options) do
      {:error, _reason} -> Jexon.to_json(["__base64__", Base.encode64(data)], options)
      x -> x
    end
  end

  def to_json(data, options) do
    Jexon.to_json(sanitize(data), options)
  end

  defp sanitize(data) when is_pid(data) do
    ["__pid__" | :erlang.pid_to_list(data)]
  end

  defp sanitize(data) when is_binary(data) do
    if String.valid?(data), do: data, else: ["__base64__", Base.encode64(data)]
  end

  defp sanitize(data) when is_reference(data) do
    ["__ref__" | :erlang.ref_to_list(data)]
  end

  defp sanitize(data) when is_port(data) do
    ["__port__" | :erlang.port_to_list(data)]
  end

  defp sanitize(data) when is_function(data) do
    ["__fun__", inspect(data)]
  end

  # Must precede the is_map/1 clause: a struct matches both and the
  # first match wins.  Map.new/2 would enumerate it, and structs do
  # not implement Enumerable.
  defp sanitize(%mod{} = data) do
    data
    |> Map.from_struct()
    |> Map.new(fn {k, v} -> {k, sanitize(v)} end)
    |> Map.put(:__struct__, mod)
  end

  defp sanitize(data) when is_map(data) do
    Map.new(data, fn {k, v} -> {k, sanitize(v)} end)
  end

  defp sanitize(data) when is_list(data) do
    Enum.map(data, &sanitize/1)
  end

  defp sanitize(data) when is_tuple(data) do
    data |> Tuple.to_list() |> Enum.map(&sanitize/1) |> List.to_tuple()
  end

  defp sanitize(data), do: data

  @spec from_json(json :: String.t()) :: {:ok, any()} | {:error, Jason.DecodeError.t()} | :error
  def from_json(data) do
    from_json(data, [])
  end

  @spec from_json(json :: String.t(), opts :: keyword()) ::
          {:ok, any()} | {:error, Jason.DecodeError.t()} | :error
  def from_json(data, options) do
    case Jexon.from_json(data, options) do
      {:ok, result} -> {:ok, desanitize(result)}
      x -> x
    end
  end

  defp desanitize(["__pid__" | rest]), do: :erlang.list_to_pid(rest)
  defp desanitize(["__base64__", encoded]), do: Base.decode64!(encoded)

  defp desanitize(data) when is_map(data) do
    Map.new(data, fn {k, v} -> {k, desanitize(v)} end)
  end

  defp desanitize(data) when is_list(data) do
    Enum.map(data, &desanitize/1)
  end

  defp desanitize(data), do: data
end
