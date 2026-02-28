defmodule GtBridge.Eval do
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

  @spec complete(GenServer.server(), String.t(), String.t() | nil) :: [String.t()]
  def complete(pid, code_prefix, source \\ nil) do
    GenServer.call(pid, {:complete, code_prefix, source})
  end

  @doc """
  I return the current bindings as a map of name→serialized value.
  Internal bindings (:port, :command_id, :pid) are filtered out.
  Non-primitive values are registered in ObjectRegistry.
  """
  @spec get_bindings(GenServer.server()) :: map()
  def get_bindings(pid) do
    GenServer.call(pid, :get_bindings)
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

  @impl true
  def handle_call(:get_bindings, _from, state = %__MODULE__{}) do
    internal = [:port, :command_id, :pid]

    result =
      state.bindings
      |> Keyword.drop(internal)
      |> Map.new(fn {name, value} ->
        exid = GtBridge.ObjectRegistry.register(value)

        serialized =
          if exid == nil do
            value
          else
            exclass = GtBridge.Resolve.data_type_to_string(value)
            %{exclass: exclass, exid: exid}
          end

        {Atom.to_string(name), serialized}
      end)

    {:reply, result, state}
  end

  # TODO garbage collect old values in the environment after a while
  @impl true
  def handle_call({:complete, code_prefix, source}, _from, state = %__MODULE__{}) do
    results = GtBridge.Completion.complete(code_prefix, state.bindings, source)
    {:reply, results, state}
  end

  @impl true
  def handle_call({:eval, string, command_id}, _from, state = %__MODULE__{}) do
    try do
      {term, new_bindings} =
        string
        |> String.replace("\r", "\n")
        |> Code.eval_string(state.bindings ++ [command_id: command_id])

      # Remove duplicated keys and ports
      unique_keys = Keyword.merge(state.bindings, Keyword.delete(new_bindings, :port))

      {:reply, term, %__MODULE__{state | bindings: unique_keys}}
    catch
      kind, e ->
        error = %GtBridge.Eval.Error{trace: __STACKTRACE__, error: e, kind: kind}
        notify(error, command_id, state.bindings[:port])

        {:reply, e, state}
    end
  end

  @spec notify(term(), String.t(), pos_integer()) :: term()
  def notify(obj, id, port) do
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
        exclass = GtBridge.Resolve.data_type_to_string(obj)

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

    Req.post!(url, json: data)

    obj
  end
end
