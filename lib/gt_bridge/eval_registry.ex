defmodule GtBridge.EvalRegistry do
  @moduledoc """
  I map session IDs to `GtBridge.Eval` processes.

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
      [{pid, _}] ->
        pid

      [] ->
        name = {:via, Registry, {@registry, session_id}}
        child_opts = Keyword.put(opts, :name, name)

        case DynamicSupervisor.start_child(EvaluationSupervisor, {Eval, child_opts}) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end
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
