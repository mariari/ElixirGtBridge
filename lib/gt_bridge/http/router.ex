defmodule GtBridge.Http.Router do
  use Plug.Router

  def call(conn, config) do
    conn
    |> assign(:pharo_client, config[:pharo_client])
    |> put_resp_content_type("application/json")
    |> super(config)
  end

  def init(opts), do: opts

  plug(:match)
  plug Plug.Parsers, parsers: [:json],
                     pass: ["application/json", "text/json"],
                     json_decoder: Jason
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

    if body["statements"] != "" do
        Eval.eval(:eval, body["statements"], body["commandId"])
    end

    conn
    |> send_resp(200, "{}")
  end
end
