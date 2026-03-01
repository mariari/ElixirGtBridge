defmodule GtBridge.Eval do
  @moduledoc """
  I am a per-session evaluation GenServer.

  Each instance corresponds to a GT view's evaluation context
  (`LeSharedSnippetContext`).  All snippets within the same view
  share one Eval process (same bindings).

  I track object IDs registered in `GtBridge.ObjectRegistry` during
  my lifetime.  When I terminate (session closed), I batch-remove
  all tracked objects from the registry.

  ## Cleanup

  GT's `BeamSessionFinalizer` sends `POST /SESSION_CLOSE` when the
  per-view `GtSharedVariablesBindings` is GC'd (page/inspector closed).
  The router calls `EvalRegistry.remove/1` which terminates me, and
  `terminate/2` batch-removes all tracked objects from the registry.
  """

  use GenServer
  use TypedStruct

  typedstruct do
    field(:bindings, Code.binding())
    field(:port, non_neg_integer(), default: nil)
    field(:registered_ids, MapSet.t(non_neg_integer()), default: MapSet.new())
  end

  def start_link(init_args) do
    name = Keyword.get(init_args, :name, nil)
    GenServer.start_link(__MODULE__, init_args, name: name)
  end

  @impl true
  def init(init_args) do
    Process.flag(:trap_exit, true)
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
        {Atom.to_string(name), register_value(value)}
      end)

    {:reply, result, collect_registered(state)}
  end

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

      {:reply, term, collect_registered(%__MODULE__{state | bindings: unique_keys})}
    catch
      kind, e ->
        error = %GtBridge.Eval.Error{trace: __STACKTRACE__, error: e, kind: kind}
        notify(error, command_id, state.bindings[:port])

        {:reply, e, collect_registered(state)}
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

  @impl true
  def terminate(_reason, state) do
    GtBridge.ObjectRegistry.remove_all(MapSet.to_list(state.registered_ids))
    :ok
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  # Register a value in ObjectRegistry.  Returns `%{exclass, exid}`
  # for complex objects, or the value as-is for primitives.
  # Accumulates IDs in the process dictionary for collection by
  # `collect_registered/1` after the call completes.
  defp register_value(value) do
    case GtBridge.ObjectRegistry.register(value) do
      nil ->
        value

      exid ->
        ids = Process.get(:_reg_ids, [])
        Process.put(:_reg_ids, [exid | ids])
        %{exclass: GtBridge.Resolve.data_type_to_string(value), exid: exid}
    end
  end

  defp collect_registered(state) do
    case Process.get(:_reg_ids) do
      nil ->
        state

      [] ->
        state

      ids ->
        Process.delete(:_reg_ids)
        new = Enum.reduce(ids, state.registered_ids, &MapSet.put(&2, &1))
        %{state | registered_ids: new}
    end
  end
end
