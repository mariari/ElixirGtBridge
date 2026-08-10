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
    # The session module's own functions, defps included, for completion
    field(:locals, [{atom(), arity()}], default: [])
    field(:port, non_neg_integer(), default: nil)
    field(:registered_ids, MapSet.t(non_neg_integer()), default: MapSet.new())
    # The evals in flight, by the ref their task answers with.
    field(:running, %{optional(reference()) => {String.t() | nil, Task.t(), GenServer.from()}},
      default: %{}
    )
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
  # OTP default 5s GenServer.call timeout would cascade any slow call
  # into a caller crash + log spam + queueing of subsequent calls.
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
  I stop the eval running under `command_id` and answer its caller a
  `GtBridge.Eval.Error` of kind `:cancelled`.

  I am how a stopped eval on the GT side stops costing anything here.
  Nothing else can interrupt user code: it runs in a task I own, and
  killing that task is the only way to take the session back.

  I answer `:ok` whether or not there was anything to kill, so a
  cancel that races the eval's own completion is not an error.
  """
  @spec cancel(GenServer.server(), String.t() | nil) :: :ok
  def cancel(pid, command_id) do
    GenServer.call(pid, {:cancel, command_id}, @call_timeout)
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

  A request already runs in its own process, so running inline gives
  the same isolation a spawned Task would.
  """
  @spec eval_stateless_sync(String.t(), String.t() | nil, pos_integer() | nil) :: term()
  def eval_stateless_sync(code, command_id, port) do
    do_eval_stateless(code, command_id, port)
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
    results =
      GtBridge.Completion.complete(code_prefix, state.bindings, source, state.env, state.locals)

    {:reply, results, state}
  end

  @impl true
  def handle_call({:eval, string, command_id}, from, state = %__MODULE__{}) do
    {:noreply, start(string, command_id, from, state)}
  end

  @impl true
  def handle_call({:cancel, command_id}, _from, state = %__MODULE__{}) do
    case Enum.find(state.running, fn {_ref, {id, _task, _from}} -> id == command_id end) do
      nil ->
        {:reply, :ok, state}

      {ref, {_id, task, from}} ->
        Task.shutdown(task, :brutal_kill)

        GenServer.reply(from, %GtBridge.Eval.Error{trace: [], error: :cancelled, kind: :cancelled})

        {:reply, :ok, %__MODULE__{state | running: Map.delete(state.running, ref)}}
    end
  end

  @impl true
  def handle_call(:flush, _from, state = %__MODULE__{}) do
    {:reply, Enum.reverse(Process.delete(:_mailbox) || []), state}
  end

  @impl true
  def handle_info({ref, answer}, state = %__MODULE__{running: running})
      when is_map_key(running, ref) do
    {{_id, _task, from}, rest} = Map.pop(running, ref)
    Process.demonitor(ref, [:flush])
    GenServer.reply(from, elem(answer, 0))
    {:noreply, apply_answer(answer, %__MODULE__{state | running: rest})}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state = %__MODULE__{running: running})
      when is_map_key(running, ref) do
    # The task died instead of answering, so its caller is still
    # waiting. A cancel never lands here: Task.shutdown flushes both.
    {{_id, _task, from}, rest} = Map.pop(running, ref)
    GenServer.reply(from, %GtBridge.Eval.Error{trace: [], error: reason, kind: :exit})
    {:noreply, %__MODULE__{state | running: rest}}
  end

  @impl true
  def handle_info({:registered, exid}, state = %__MODULE__{}) do
    {:noreply, track([exid], state)}
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
    case Process.get(:_session) do
      nil ->
        case Process.delete(:_mailbox) do
          nil -> []
          msgs -> Enum.reverse(msgs)
        end

      session ->
        # I run in the task, but messages arrive at the session, which
        # is the process the `pid` binding names and the one worth
        # subscribing to -- it outlives me.
        GenServer.call(session, :flush, @call_timeout)
    end
  end

  @doc """
  I register each element of `list` and return what GT dresses as a
  proxy, leaving primitives inline.

  `GtBridge.Serializer.to_json` inlines a struct as a plain map, so a
  list fetched through it arrives as data with no remote identity. I
  give each element the same `%{exclass, exid}` reference an eval
  result gets, in one call rather than one per element.

      [1, URI.parse("http://a.b")] |> references()
  """
  @spec references(list()) :: list()
  def references(list) do
    Enum.map(list, &register_value/1)
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  # The task carries my pid so flush/0 can find the mailbox messages
  # arrive at.
  @spec start(String.t(), String.t() | nil, GenServer.from(), t()) :: t()
  defp start(string, command_id, from, state) do
    session = self()

    task =
      Task.Supervisor.async_nolink(GtBridge.EvalTaskSupervisor, fn ->
        Process.put(:_session, session)
        run(string, command_id, state)
      end)

    %__MODULE__{state | running: Map.put(state.running, task.ref, {command_id, task, from})}
  end

  @spec run(String.t(), String.t() | nil, t()) ::
          {term(), Code.binding(), Macro.Env.t(), [non_neg_integer()]}
  defp run(string, command_id, state) do
    quoted =
      string
      |> String.replace("\r", "\n")
      |> Code.string_to_quoted!()

    {term, new_bindings, new_env} =
      Code.eval_quoted_with_env(quoted, state.bindings ++ [command_id: command_id], state.env)

    # The snippet may have defined modules; enter them into the record.
    GtBridge.Analysis.LoadedModules.sync_async()

    {term, new_bindings, new_env, Process.get(:_reg_ids, [])}
  catch
    kind, e ->
      error = %GtBridge.Eval.Error{trace: __STACKTRACE__, error: e, kind: kind}
      {error, nil, nil, Process.get(:_reg_ids, [])}
  end

  # A failed eval keeps the bindings it started with; a half-applied
  # set is worse than none.
  @spec apply_answer(
          {term(), Code.binding() | nil, Macro.Env.t() | nil, [non_neg_integer()]},
          t()
        ) ::
          t()
  defp apply_answer({_term, nil, nil, ids}, state) do
    track(ids, state)
  end

  defp apply_answer({_term, new_bindings, new_env, ids}, state) do
    # Remove duplicated keys and ports
    unique_keys = Keyword.merge(state.bindings, Keyword.delete(new_bindings, :port))
    track(ids, %__MODULE__{state | bindings: unique_keys, env: merge_env(state.env, new_env)})
  end

  # Bindings merge, so the env has to as well: two evals in flight both
  # start from my env and each answers with its own, and assigning the
  # last one to arrive drops the other's aliases.  Only these three
  # fields can differ between envs grown from the same one.
  @spec merge_env(Macro.Env.t(), Macro.Env.t()) :: Macro.Env.t()
  defp merge_env(old, new) do
    %{
      old
      | aliases: Keyword.merge(old.aliases, new.aliases),
        requires: Enum.uniq(old.requires ++ new.requires),
        functions:
          Keyword.merge(old.functions, new.functions, fn _m, a, b -> Enum.uniq(a ++ b) end)
    }
  end

  @spec track([non_neg_integer()], t()) :: t()
  defp track(ids, state) do
    %__MODULE__{state | registered_ids: Enum.into(ids, state.registered_ids)}
  end

  # Register a value in ObjectRegistry.  Returns `%{exclass, exid}`
  # for complex objects, or the value as-is for primitives.
  # Accumulates IDs in the process dictionary for collection by
  # `collect_registered/1` after the call completes.
  defp register_value(value) do
    case GtBridge.ObjectRegistry.register(value) do
      nil ->
        value

      exid ->
        # Tell the session now rather than handing back a list at the
        # end: a cancelled eval is killed mid-flight, and a batch it
        # never got to return would leave its objects in the registry
        # with nothing tracking them.
        case Process.get(:_session) do
          nil -> Process.put(:_reg_ids, [exid | Process.get(:_reg_ids, [])])
          session -> send(session, {:registered, exid})
        end

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
