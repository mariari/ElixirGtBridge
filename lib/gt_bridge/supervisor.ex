defmodule GtBridge.Supervisor do
  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    children = [{EvaluationSupervisor, [{Eval, name: :eval}]}, {Tcp.Supervisor, []}, {GtBridge.Http.Supervisor, []}]
    Supervisor.init(children, strategy: :one_for_one)
  end

  def eval(statements) do
    Eval.eval(pid, statements)
  end
end
