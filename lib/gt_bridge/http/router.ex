defmodule GtBridge.Http.Router do
  use Plug.Router

  alias GtBridge.Eval

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

  # It seems we don't do anything here
  post "/IS_ALIVE" do
    send_resp(conn, 200, JSON.encode!("IS_ALIVE"))
  end

  # We get a notify to begin with, we should forward it properly
  post "/ENQUEUE" do
    {:ok, _, conn} = Plug.Conn.read_body(conn)
    body = conn.body_params

    require Logger
    Logger.info("ENQUEUE received: #{inspect(body)}")

    if body["statements"] != "" do
      Eval.eval(:eval, body["statements"], body["commandId"])
    end

    # Always return empty JSON like Python bridge does
    conn
    |> send_resp(200, "{}")
  end

  # Receive notifications/callbacks (GT might POST here)
  post "/EVAL" do
    {:ok, _, conn} = Plug.Conn.read_body(conn)
    body = conn.body_params

    require Logger
    Logger.info("Received EVAL callback: #{inspect(body)}")

    conn
    |> send_resp(200, Jason.encode!(%{success: true}))
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
          # Try to get the object from the eval context
          case Eval.eval(:eval, object_id, nil) do
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
end
