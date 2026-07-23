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
    field(:env, Macro.Env.t())
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
    # `pid` gives snippets their session process (self() also works;
    # the binding frees `self` for the inspector's inspected object).
    default_bindings = if port, do: [pid: self(), port: port], else: [pid: self()]
    {:ok, %__MODULE__{bindings: default_bindings, env: GtBridge.Eval.Env.env(), port: port}}
  end

  ############################################################
  #                      Public RPC API                      #
  ############################################################

  # User code under eval can legitimately take arbitrarily long. The
  # OTP default 5s GenServer.call timeout cascades any slow call into
  # a Cowboy worker crash + log spam + queueing of subsequent calls.
  # Wait as long as the work needs.
  @call_timeout :infinity

  @spec eval(GenServer.server(), String.t(), String.t() | nil) :: any()
  def eval(pid, code, command_id) do
    GenServer.call(pid, {:eval, code, command_id}, @call_timeout)
  end

  @spec complete(GenServer.server(), String.t(), String.t() | nil) :: [String.t()]
  def complete(pid, code_prefix, source \\ nil) do
    GenServer.call(pid, {:complete, code_prefix, source}, @call_timeout)
  end

  @doc """
  I return the current bindings as a map of name→serialized value.
  Internal bindings (:port, :command_id, :pid) are filtered out.
  Non-primitive values are registered in ObjectRegistry.
  """
  @spec get_bindings(GenServer.server()) :: map()
  def get_bindings(pid) do
    GenServer.call(pid, :get_bindings, @call_timeout)
  end

  @doc """
  Remove an object from the registry.
  Called by GT when a proxy object is garbage collected.
  """
  @spec remove(non_neg_integer()) :: :ok
  def remove(id) do
    GtBridge.ObjectRegistry.remove(id)
  end

  @doc """
  I encode an evaluation result for the wire.

  I register complex values in `GtBridge.ObjectRegistry` and send an
  `%{exid, exclass}` reference, so GT receives a proxy it can inspect
  lazily rather than a fully materialised copy.  Primitives travel by
  value.
  """
  @spec encode_result(term()) :: String.t()
  def encode_result(obj) do
    {:ok, json} =
      case register_value(obj) do
        registered = %{exid: _} -> Jason.encode(registered)
        primitive -> GtBridge.Serializer.to_json(primitive)
      end

    json
  end

  @doc """
  I evaluate in the calling process and return the value, so the answer
  can travel back in the HTTP response rather than as a second message.

  The Task in `eval_stateless/3` existed to keep concurrent queries off
  one shared mailbox; a Cowboy request already has its own process, so
  running inline gives the same isolation.
  """
  @spec eval_stateless_sync(String.t(), String.t() | nil, pos_integer() | nil) :: term()
  def eval_stateless_sync(code, command_id, port) do
    do_eval_stateless(code, command_id, port)
  end

  @doc """
  I evaluate `code` in a fresh process with no per-page bindings.

  GT-side `evaluateAndWait` calls that don't pass a `sessionId` (view-
  block fetches, proxy-GC finalizers, browser fan-out queries) used
  to land on a single shared "default" Eval GenServer, which
  serialized them through one mailbox and cascaded any slow call
  into a Cowboy worker timeout storm.

  Per-page snippet evals still use the session-bound `eval/3` path so
  bindings persist across snippets on the same page. This stateless
  path is for everything else — parallelism is bounded only by the
  BEAM scheduler, not by a shared GenServer.

  Registered objects in ObjectRegistry live until GT GCs the
  corresponding proxy and fires `Eval.remove/1`.
  """
  @spec eval_stateless(String.t(), String.t() | nil, pos_integer() | nil) :: :ok
  def eval_stateless(code, command_id, port) do
    Task.start(fn -> do_eval_stateless(code, command_id, port) end)

    :ok
  end

  @spec do_eval_stateless(String.t(), String.t() | nil, pos_integer() | nil) :: term()
  defp do_eval_stateless(code, command_id, port) do
    try do
      quoted =
        code
        |> String.replace("\r", "\n")
        |> Code.string_to_quoted!()

      bindings =
        if port,
          do: [pid: self(), port: port, command_id: command_id],
          else: [pid: self(), command_id: command_id]

      {value, _binding, _env} =
        Code.eval_quoted_with_env(quoted, bindings, GtBridge.Eval.Env.env())

      GtBridge.Analysis.LoadedModules.sync_async()
      value
    catch
      kind, e ->
        %GtBridge.Eval.Error{trace: __STACKTRACE__, error: e, kind: kind}
    end
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
    results = GtBridge.Completion.complete(code_prefix, state.bindings, source, state.env)
    {:reply, results, state}
  end

  @impl true
  def handle_call({:eval, string, command_id}, _from, state = %__MODULE__{}) do
    try do
      quoted =
        string
        |> String.replace("\r", "\n")
        |> Code.string_to_quoted!()

      {term, new_bindings, new_env} =
        Code.eval_quoted_with_env(
          quoted,
          state.bindings ++ [command_id: command_id],
          state.env
        )

      # The snippet may have defined modules; enter them into the record.
      GtBridge.Analysis.LoadedModules.sync_async()

      # Remove duplicated keys and ports
      unique_keys = Keyword.merge(state.bindings, Keyword.delete(new_bindings, :port))

      {:reply, term, collect_registered(%__MODULE__{state | bindings: unique_keys, env: new_env})}
    catch
      kind, e ->
        error = %GtBridge.Eval.Error{trace: __STACKTRACE__, error: e, kind: kind}
        {:reply, error, collect_registered(state)}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Process.put(:_mailbox, [msg | Process.get(:_mailbox, [])])
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    GtBridge.ObjectRegistry.remove_all(MapSet.to_list(state.registered_ids))
    :ok
  end

  ############################################################
  #                     Eval Built-ins                       #
  ############################################################

  @doc """
  I return documentation for a module, function, or type.

  Bound as `h` in every eval session. Because I am a macro, I can
  parse dot-syntax like `h(Enum.map)` and `h(Enum.map/2)`.

      h(Enum)
      h(Enum.map)
      h(Enum.map/2)
      h({Enum, :map})
      h({Enum, :map, 2})
  """
  defmacro h({:/, _, [{{:., _, [mod, fun]}, _, _}, arity]}) do
    quote do: GtBridge.Documentation.for_function(unquote(mod), unquote(fun), unquote(arity))
  end

  defmacro h({{:., _, [mod, fun]}, _, _}) do
    quote do: GtBridge.Documentation.for_function(unquote(mod), unquote(fun))
  end

  defmacro h(other) do
    quote do
      case unquote(other) do
        m when is_atom(m) -> GtBridge.Documentation.for_module(m)
        {m, f} -> GtBridge.Documentation.for_function(m, f)
        {m, f, a} -> GtBridge.Documentation.for_function(m, f, a)
      end
    end
  end

  @doc """
  I drain and return all messages received by the eval process.

  Like IEx's `flush/0`. Useful when user code subscribes the eval
  process to event brokers and you want to see what arrived.

      flush()
  """
  @spec flush() :: [term()]
  def flush do
    case Process.delete(:_mailbox) do
      nil -> []
      msgs -> Enum.reverse(msgs)
    end
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
