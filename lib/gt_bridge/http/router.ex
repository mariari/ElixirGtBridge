defmodule GtBridge.Http.Router do
  use Plug.Router

  alias GtBridge.Eval
  alias GtBridge.EvalRegistry

  def call(conn, config) do
    conn
    |> assign(:pharo_client, config[:pharo_client])
    |> put_resp_content_type("application/json")
    |> super(config)
  end

  def init(opts), do: opts

  plug(:match)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json", "text/json"],
    json_decoder: Jason
  )

  plug(:dispatch)

  get "/" do
    port = conn.assigns.pharo_client

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "Plug!, Options: #{port}")
  end

  # `/EVENTS` is handled by `GtBridge.Http.Supervisor.listener_opts/2` at the
  # cowboy dispatch level.

  # It seems we don't do anything here
  post "/IS_ALIVE" do
    send_resp(conn, 200, JSON.encode!("IS_ALIVE"))
  end

  post "/ENQUEUE" do
    {:ok, _, conn} = Plug.Conn.read_body(conn)
    body = conn.body_params

    result =
      if body["statements"] != "" do
        port = conn.assigns.pharo_client

        case body["sessionId"] do
          nil ->
            # No session = no per-page bindings needed. Run inline: each
            # request already has its own Cowboy process, which is the
            # same isolation a Task gave, and running here lets the
            # answer travel back in this response.
            Eval.eval_stateless_sync(body["statements"], body["commandId"], port)

          sid ->
            # Session-bound: snippet evals on a Lepiter page need
            # bindings persisted across snippets, so route to the
            # per-page Eval GenServer.
            eval = EvalRegistry.get_or_create(sid, port: port)
            Eval.eval(eval, body["statements"], body["commandId"])
        end
      end

    # Carry the answer in the response, encoded as the callback used to
    # encode it, so complex results stay proxies.
    value_json = Eval.encode_result(result)
    body_out = Jason.encode!(%{type: "EVAL", id: body["commandId"], value: value_json})

    conn
    |> send_resp(200, body_out)
  end

  post "/COMPLETE" do
    {:ok, _, conn} = Plug.Conn.read_body(conn)
    body = conn.body_params
    code = body["code"] || ""
    source = body["source"]
    eval = resolve_eval(conn, body)
    results = Eval.complete(eval, code, source)

    conn
    |> send_resp(200, Jason.encode!(results))
  end

  post "/BINDINGS" do
    {:ok, _, conn} = Plug.Conn.read_body(conn)
    body = conn.body_params
    eval = resolve_eval(conn, body)
    bindings = Eval.get_bindings(eval)

    {:ok, json} = GtBridge.Serializer.to_json(bindings)

    conn
    |> send_resp(200, json)
  end

  # Get view specifications for an object
  post "/GET_VIEWS" do
    {:ok, _, conn} = Plug.Conn.read_body(conn)
    body = conn.body_params

    # The body should contain an object reference or serialized object
    # For now, we'll expect a variable name that was bound in the eval context
    response =
      case body do
        %{"objectId" => object_id} ->
          eval = resolve_eval(conn, body)

          # Try to get the object from the eval context
          case Eval.eval(eval, object_id, nil) do
            %{__struct__: _module} = object ->
              views = GtBridge.View.get_view_object(object)
              Jason.encode!(%{views: views})

            _ ->
              Jason.encode!(%{error: "Object not found or has no views"})
          end

        _ ->
          Jason.encode!(%{error: "Invalid request"})
      end

    conn
    |> send_resp(200, response)
  end

  post "/SESSION_CLOSE" do
    {:ok, _, conn} = Plug.Conn.read_body(conn)
    body = conn.body_params
    session_id = body["sessionId"]

    if session_id do
      EvalRegistry.remove(session_id)
    end

    conn
    |> send_resp(200, "{}")
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  defp resolve_eval(conn, body) do
    session_id = body["sessionId"] || "default"
    port = conn.assigns.pharo_client
    EvalRegistry.get_or_create(session_id, port: port)
  end
end
