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
    try do
      {term, new_bindings} =
        string
        |> String.replace("\r", "\n")
        |> Code.eval_string(state.bindings ++ [command_id: command_id, self: self()])

      # Remove duplicated keys and ports
      unique_keys = Keyword.merge(state.bindings, Keyword.delete(new_bindings, :port))

      {:reply, term, %__MODULE__{state | bindings: unique_keys}}
    rescue
      e ->
        # Replace this with a proper eval strategy reply wise, it
        # isn't proper that we are manually calling notify here,
        # assumes too much context
        Code.eval_string(
          "Eval.notify(#{inspect({e, __STACKTRACE__})}, command_id, port)",
          state.bindings ++ [command_id: command_id]
        )

        {:reply, e, state}
    end
  end

  @spec notify(term(), String.t(), pos_integer()) :: term()
  def notify(obj, id, port) do
    require Logger
    Logger.info("Notify called: obj=#{inspect(obj)}, id=#{id}, port=#{port}")

    # Register the object and get a unique ID (nil for primitives)
    exid = GtBridge.ObjectRegistry.register(obj)

    # If it's a primitive (exid is nil), send it directly without wrapping
    value_json_string =
      if exid == nil do
        # Primitive - send as-is, use our own serializer to get around
        # atoms and binary
        {:ok, json} = GtBridge.Serializer.to_json(obj)
        json
      else
        # Complex object - wrap with metadata (lazy loading, no value)
        # Get class info for the object
        exclass =
          IEx.Info.info(obj)
          |> Enum.find({"Data type", "Unknown"}, fn {x, _} -> "Data type" == x end)
          |> elem(1)

        # The value object with metadata (no value field for lazy loading)
        value_object = %{
          exclass: exclass,
          exid: exid
        }

        {:ok, json} = Jason.encode(value_object)
        json
      end

    data = %{
      type: "EVAL",
      id: id,
      value: value_json_string,
      __sync: "_"
    }

    url = "http://localhost:" <> to_string(port) <> "/EVAL"
    Logger.info("POSTing to #{url} with data: #{inspect(data)}")

    response = Req.post!(url, json: data)
    Logger.info("POST response: #{inspect(response)}")

    obj
  end
end
