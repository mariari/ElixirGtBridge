defmodule Eval do
  use GenServer
  use TypedStruct

  typedstruct do
    field(:bindings, Code.binding())
    field(:port, non_neg_integer(), default: nil)
  end

  def start_link(init_args) do
    name = Keyword.get(init_args, :name, nil)
    GenServer.start_link(__MODULE__, init_args, name: name)
  end

  @impl true
  def init(init_args) do
    port = Keyword.get(init_args, :port, nil)
    default_bindings = if port, do: [port: port], else: []
    {:ok, %__MODULE__{bindings: default_bindings, port: port}}
  end

  ############################################################
  #                      Public RPC API                      #
  ############################################################

  @spec eval(GenServer.server(), String.t(), String.t() | nil) :: any()
  def eval(pid, code, command_id) do
    GenServer.call(pid, {:eval, code, command_id})
  end

  @doc """
  Remove an object from the registry.
  Called by GT when a proxy object is garbage collected.
  """
  @spec remove(non_neg_integer()) :: :ok
  def remove(id) do
    GtBridge.ObjectRegistry.remove(id)
  end

  ############################################################
  #                    Genserver Behavior                    #
  ############################################################

  # TODO garbage collect old values in the environment after a while
  @impl true
  def handle_call({:eval, string, command_id}, _from, state = %__MODULE__{}) do
    {term, new_bindings} =
      string
      |> String.replace("\r", "\n")
      |> Code.eval_string(state.bindings ++ [command_id: command_id])

    # Remove duplicated keys and ports
    unique_keys = Keyword.merge(state.bindings, Keyword.delete(new_bindings, :port))

    {:reply, term, %__MODULE__{state | bindings: unique_keys}}
  end

  @spec notify(term(), String.t(), pos_integer()) :: term()
  def notify(obj, id, port) do
    require Logger
    Logger.info("Notify called: obj=#{inspect(obj)}, id=#{id}, port=#{port}")

    # Register the object and get a unique ID
    exid = GtBridge.ObjectRegistry.register(obj)

    # Get class info for the object
    exclass =
      IEx.Info.info(obj)
      |> Enum.find({"Data type", "Unknown"}, fn {x, _} -> "Data type" == x end)
      |> elem(1)

    # Convert struct to a JSON-encodable format
    json_value = struct_to_json_value(obj)

    # The value object with metadata
    value_object = %{
      exclass: exclass,
      # Use the real registry ID
      exid: exid,
      value: json_value
    }

    # Serialize the value object to a JSON string
    # GT expects this to be a string that it can parse.
    # We use our own serializer to get around pids, binary and atoms
    # not turning into JSON.
    {:ok, value_json_string} =  GtBridge.Serializer.to_json(value_object)

    data = %{
      type: "EVAL",
      id: id,
      # JSON string, not a map
      value: value_json_string,
      __sync: "_"
    }

    url = "http://localhost:" <> to_string(port) <> "/EVAL"
    Logger.info("POSTing to #{url} with data: #{inspect(data)}")

    response = Req.post!(url, json: data)
    Logger.info("POST response: #{inspect(response)}")

    obj
  end

  # Convert a struct to a JSON-encodable value
  defp struct_to_json_value(%{__struct__: module} = struct) do
    # Convert struct to a map with string keys
    struct
    |> Map.from_struct()
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.put("__struct__", inspect(module))
  end

  defp struct_to_json_value(value), do: value
end
