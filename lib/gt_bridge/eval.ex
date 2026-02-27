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
        {Atom.to_string(name), register_value(value)}
      end)

    {:reply, result, state}
  end

  # TODO garbage collect old values in the environment after a while
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
    registered = register_value(obj)

    {:ok, value_json_string} =
      case registered do
        %{exid: _} -> Jason.encode(registered)
        primitive -> GtBridge.Serializer.to_json(primitive)
      end

    data = %{type: "EVAL", id: id, value: value_json_string, __sync: "_"}
    url = "http://localhost:" <> to_string(port) <> "/EVAL"
    Req.post!(url, json: data)

    obj
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  # Register a value in ObjectRegistry.  Returns `%{exclass, exid}`
  # for complex objects, or the value as-is for primitives.
  defp register_value(value) do
    case GtBridge.ObjectRegistry.register(value) do
      nil -> value
      exid -> %{exclass: GtBridge.Resolve.data_type_to_string(value), exid: exid}
    end
  end
end
