defmodule GtBridge.Supervisor do
  use Supervisor

  def start_link(args \\ []) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    children = [
      {EvaluationSupervisor, []},
      {Tcp.Supervisor, []},
      {GtBridge.Http.Supervisor, []},
      {GtBridge.Views, [name: GtBridge.Views]},
      {GtBridge.ObjectRegistry, [name: GtBridge.ObjectRegistry]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
