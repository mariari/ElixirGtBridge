defmodule GtBridge.EvalRegistry do
  @moduledoc """
  I map session IDs to `GtBridge.Eval` processes.

  A session maps to a single evaluation context in GT — one page
  view or one inspector view.  All snippets within the same view
  share a session (same bindings).  Opening the same page twice
  creates two sessions.

  On the GT side, the scope object is `GtSharedVariablesBindings`
  (inside `LeSharedSnippetContext`).  It is created per
  `LePageViewModel` and propagated to all snippet view models.
  The session ID (a UUID) is stored in a class-side
  `WeakIdentityKeyDictionary` on `LeElixirSnippetElement`,
  identity-keyed on the bindings object.

  Sessions are created on demand (first eval) and removed when
  GT's `BeamSessionFinalizer` fires on GC of the shared bindings
  object, sending `POST /SESSION_CLOSE`.

  I use an Elixir `Registry` for lookup and start new Eval processes
  under `EvaluationSupervisor` on demand.  Sessions without a
  `sessionId` use `"default"` for backward compatibility.

  ### Public API

  - `get_or_create/2` — return the Eval pid for a session, starting one if needed.
  - `remove/1` — stop and unregister the Eval for a session.
  """

  alias GtBridge.Eval

  @registry __MODULE__

  ############################################################
  #                        Public API                        #
  ############################################################

  @doc "I return the Eval pid for session_id, starting one if needed."
  @spec get_or_create(String.t(), keyword()) :: GenServer.server()
  def get_or_create(session_id, opts \\ []) do
    case Registry.lookup(@registry, session_id) do
      [{pid, _}] when is_pid(pid) ->
        if Process.alive?(pid), do: pid, else: start_eval(session_id, opts)

      _ ->
        start_eval(session_id, opts)
    end
  end

  defp start_eval(session_id, opts) do
    name = {:via, Registry, {@registry, session_id}}
    child_opts = Keyword.put(opts, :name, name)

    case DynamicSupervisor.start_child(EvaluationSupervisor, {Eval, child_opts}) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  @doc "I stop and unregister the Eval for session_id."
  @spec remove(String.t()) :: :ok
  def remove(session_id) do
    case Registry.lookup(@registry, session_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(EvaluationSupervisor, pid)
      [] -> :ok
    end
  end
end
