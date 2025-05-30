defmodule GtBridge.Http.Supervisor do
  # We may startup many servers and none by default
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_listener(port_server, port_client) do
    eval = Process.whereis(:eval)

    DynamicSupervisor.start_child(
      __MODULE__,
      {Plug.Cowboy,
       scheme: :http,
       plug: {GtBridge.Http.Router, %{pharo_client: port_client, eval: eval}},
       port: port_server}
    )
  end

  # We don't have any children by default wait until one spawns it up
  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
