defmodule Examples.EEval do
  @moduledoc """
  I am examples for GtBridge.Eval, the evaluation GenServer.
  """

  use ExExample

  import ExUnit.Assertions

  alias GtBridge.Eval
  alias GtBridge.EvalRegistry

  def rerun?(_), do: true

  @spec new_eval() :: pid()
  example new_eval do
    {:ok, pid} = DynamicSupervisor.start_child(EvaluationSupervisor, {Eval, []})

    assert Process.alive?(pid)

    pid
  end

  @spec new_eval_with_port(pos_integer()) :: pid()
  example new_eval_with_port(port \\ :rand.uniform(10000)) do
    {:ok, pid} = DynamicSupervisor.start_child(EvaluationSupervisor, {Eval, [port: port]})

    assert Process.alive?(pid)

    pid
  end

  @spec port_is_always_bound(pos_integer()) :: pid()
  example port_is_always_bound(port \\ :rand.uniform(10000)) do
    pid = new_eval_with_port(port)
    Eval.eval(pid, "port = 0.22", nil)

    assert Eval.eval(pid, "port", nil) == port

    pid
  end

  @doc """
  I prove snippets can reach their session process through the `pid`
  binding (named `pid`, not `self`, so the inspector can bind `self`
  to the inspected object) and that /BINDINGS filters it as internal.
  Returns the session.
  """
  @spec pid_binds_the_session_process() :: pid()
  example pid_binds_the_session_process do
    pid = new_eval()

    assert Eval.eval(pid, "pid", nil) == pid
    assert Eval.eval(pid, "send(pid, :from_snippet) == :from_snippet", nil) == true
    refute Map.has_key?(Eval.get_bindings(pid), "pid")

    pid
  end

  @spec bind_a_to_30() :: pid()
  example bind_a_to_30 do
    pid = new_eval()
    Eval.eval(pid, "a = 30", nil)

    assert Eval.eval(pid, "a", nil) == 30

    pid
  end

  example rebind_a_to_a do
    pid = bind_a_to_30()
    Eval.eval(pid, "a = :a", nil)

    assert Eval.eval(pid, "a", nil) == :a

    pid
  end

  @spec sessions_are_isolated() :: {pid(), pid()}
  example sessions_are_isolated do
    page_a = "page-" <> Integer.to_string(:rand.uniform(100_000))
    page_b = "page-" <> Integer.to_string(:rand.uniform(100_000))

    eval_a = EvalRegistry.get_or_create(page_a)
    eval_b = EvalRegistry.get_or_create(page_b)

    assert eval_a != eval_b

    Eval.eval(eval_a, "x = 1", nil)
    Eval.eval(eval_b, "x = 2", nil)

    assert Eval.eval(eval_a, "x", nil) == 1
    assert Eval.eval(eval_b, "x", nil) == 2

    EvalRegistry.remove(page_a)
    EvalRegistry.remove(page_b)

    {eval_a, eval_b}
  end

  @spec session_get_or_create_is_idempotent() :: pid()
  example session_get_or_create_is_idempotent do
    session = "idem-" <> Integer.to_string(:rand.uniform(100_000))

    pid1 = EvalRegistry.get_or_create(session)
    pid2 = EvalRegistry.get_or_create(session)

    assert pid1 == pid2

    EvalRegistry.remove(session)

    pid1
  end

  @spec session_remove_cleans_up() :: :ok
  example session_remove_cleans_up do
    session = "cleanup-" <> Integer.to_string(:rand.uniform(100_000))

    pid = EvalRegistry.get_or_create(session)
    assert Process.alive?(pid)

    EvalRegistry.remove(session)
    refute Process.alive?(pid)

    # A new get_or_create after removal starts a fresh process
    new_pid = EvalRegistry.get_or_create(session)
    assert new_pid != pid
    assert Process.alive?(new_pid)

    EvalRegistry.remove(session)

    :ok
  end

  @spec terminate_cleans_object_registry() :: :ok
  example terminate_cleans_object_registry do
    session = "obj-cleanup-" <> Integer.to_string(:rand.uniform(100_000))

    pid = EvalRegistry.get_or_create(session)

    # Eval and bind a non-primitive — gets registered in ObjectRegistry
    Eval.eval(pid, "x = %{c: 3}", nil)
    bindings = Eval.get_bindings(pid)
    assert Map.has_key?(bindings, "x")
    exid = bindings["x"].exid
    assert exid != nil

    # Object is in the registry before termination
    assert GtBridge.ObjectRegistry.get(exid) != :error

    # Terminate the session
    EvalRegistry.remove(session)
    refute Process.alive?(pid)

    # Object has been cleaned up from the registry
    assert GtBridge.ObjectRegistry.get(exid) == :error

    :ok
  end

  @spec cancel_frees_the_session() :: :ok
  example cancel_frees_the_session do
    {:ok, pid} = DynamicSupervisor.start_child(EvaluationSupervisor, {Eval, []})
    caller = self()
    spin = "Stream.repeatedly(fn -> :x end) |> Enum.to_list()"

    spawn(fn -> send(caller, {:spun, Eval.eval(pid, spin, "spin")}) end)
    Process.sleep(200)

    # The session answers while user code runs: the eval is in a task,
    # not in the GenServer, which is what a cancel needs to be possible.
    assert Eval.complete(pid, "Enu", nil) != []

    # A second eval queues behind the first rather than clobbering it.
    spawn(fn -> send(caller, {:queued, Eval.eval(pid, "40 + 2", "queued")}) end)
    Process.sleep(100)

    assert Eval.cancel(pid, "spin") == :ok

    assert_receive {:spun, %GtBridge.Eval.Error{kind: :cancelled}}, 3_000
    # Killing the head of the queue lets what was behind it through.
    assert_receive {:queued, 42}, 3_000

    # Bindings survive a cancelled neighbour.
    assert Eval.eval(pid, "x = 7", nil) == 7
    assert Eval.eval(pid, "x * 6", nil) == 42

    :ok
  end

  @spec cancel_tracks_what_the_killed_eval_registered() :: :ok
  example cancel_tracks_what_the_killed_eval_registered do
    session = "cancel-cleanup-" <> Integer.to_string(:rand.uniform(100_000))
    pid = EvalRegistry.get_or_create(session)
    caller = self()

    code =
      "GtBridge.Eval.encode_result(URI.parse(\"http://a.b\"));" <>
        "Stream.repeatedly(fn -> :x end) |> Enum.to_list()"

    spawn(fn -> send(caller, {:spun, Eval.eval(pid, code, "spin")}) end)
    Process.sleep(300)
    Eval.cancel(pid, "spin")
    assert_receive {:spun, %GtBridge.Eval.Error{kind: :cancelled}}, 3_000

    # The killed task never handed its ids back, so it reports each one
    # as it registers; otherwise these would outlive the session.
    tracked = :sys.get_state(pid).registered_ids
    assert MapSet.size(tracked) > 0
    assert Enum.all?(tracked, &(GtBridge.ObjectRegistry.get(&1) != :error))

    EvalRegistry.remove(session)
    Process.sleep(100)
    assert Enum.all?(tracked, &(GtBridge.ObjectRegistry.get(&1) == :error))

    :ok
  end
end
