defmodule Tcp.Dispatch do
  @moduledoc """
  I turn one decoded request frame into the reply frame for it.

  I am transport-free on purpose: `Tcp.Connection` owns the socket, I
  own what a request means.  The HTTP router still answers the same
  messages while both transports are live, so I mirror its
  session/stateless split exactly.
  """

  alias GtBridge.Eval
  alias GtBridge.EvalRegistry

  @doc """
  I answer `request` with the map to send back.

  Every reply carries the `id` its request arrived with, so GT can
  match it to a pending promise no matter what order replies return in.
  """
  @spec reply_to(map()) :: map()
  def reply_to(%{"type" => "ENQUEUE"} = request) do
    %{type: "EVAL", id: request["commandId"], value: Eval.encode_result(evaluate(request))}
  end

  def reply_to(%{"type" => "IS_ALIVE"} = request) do
    %{type: "IS_ALIVE", id: request["commandId"]}
  end

  def reply_to(request) do
    %{type: "ERROR", id: request["commandId"], error: "unknown type #{inspect(request["type"])}"}
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  defp evaluate(%{"statements" => ""}), do: nil

  defp evaluate(%{"sessionId" => session_id} = request) when is_binary(session_id) do
    # Snippets on a Lepiter page need bindings to persist between them,
    # so these go to the per-page Eval.
    eval = EvalRegistry.get_or_create(session_id, port: nil)
    Eval.eval(eval, request["statements"], request["commandId"])
  end

  defp evaluate(request) do
    # No session means no per-page bindings to keep; each request runs
    # in the connection's task, which is the isolation the Cowboy
    # process gave.  `port: nil` -- the reply is the only route back.
    Eval.eval_stateless_sync(request["statements"], request["commandId"], nil)
  end
end
