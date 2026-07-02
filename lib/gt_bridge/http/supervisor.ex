defmodule GtBridge.Http.Supervisor do
  # We may startup many servers and none by default
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_listener(port_server, port_client) do
    # Bridge is coming up: begin xref indexing now (deferred from VM boot).
    GtBridge.Xref.start_indexing()

    DynamicSupervisor.start_child(
      __MODULE__,
      {Plug.Cowboy, listener_opts(port_server, port_client)}
    )
  end

  # `:dispatch` overrides `:plug` for routing. `/EVENTS` goes to the
  # cowboy_loop handler directly (no plug pipeline), everything else
  # flows through the router.  `:plug` is still required for the
  # child_spec to validate.
  @spec listener_opts(:inet.port_number(), :inet.port_number()) :: keyword()
  defp listener_opts(port_server, port_client) do
    router_opts = {GtBridge.Http.Router, %{pharo_client: port_client}}

    [
      scheme: :http,
      plug: router_opts,
      port: port_server,
      dispatch: [
        {:_,
         [
           {"/EVENTS", GtBridge.Http.SseStream, []},
           {:_, Plug.Cowboy.Handler, router_opts}
         ]}
      ]
    ]
  end

  # We don't have any children by default wait until one spawns it up
  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
