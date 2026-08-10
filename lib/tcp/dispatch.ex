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
  I answer `request` with the map to send back, or `:no_reply` when the
  request wants none.

  Every reply carries the `id` its request arrived with and the uniform
  type `"EVAL"` -- an answer for a command id -- so GT resolves the
  waiting promise no matter which channel asked.  The request's own type
  routes what runs; only the value's encoding differs: an eval result is
  registered as a proxy, a completion list stays a plain list.
  """
  @spec reply_to(map()) :: map() | :no_reply
  def reply_to(%{"type" => "ENQUEUE"} = request) do
    answer(request, Eval.encode_result(evaluate(request)))
  end

  def reply_to(%{"type" => "CANCEL"} = request) do
    # GT sends me when the user stops waiting.  Without me the eval
    # keeps running and every later request for that session queues
    # behind it, which is how a stopped snippet used to wedge a page.
    Eval.cancel(resolve_eval(request), request["commandId"])
    :no_reply
  end

  def reply_to(%{"type" => "COMPLETE"} = request) do
    results = Eval.complete(resolve_eval(request), request["code"] || "", request["source"])
    answer(request, Jason.encode!(results))
  end

  def reply_to(%{"type" => "BINDINGS"} = request) do
    {:ok, json} = GtBridge.Serializer.to_json(Eval.get_bindings(resolve_eval(request)))
    answer(request, json)
  end

  def reply_to(%{"type" => "SESSION_CLOSE"} = request) do
    if sid = request["sessionId"], do: EvalRegistry.remove(sid)
    :no_reply
  end

  def reply_to(%{"type" => "IS_ALIVE"} = request) do
    answer(request, Jason.encode!("IS_ALIVE"))
  end

  def reply_to(request) do
    %{type: "ERROR", id: request["commandId"], error: "unknown type #{inspect(request["type"])}"}
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  defp answer(request, value_json) do
    %{type: "EVAL", id: request["commandId"], value: value_json}
  end

  defp resolve_eval(request) do
    EvalRegistry.get_or_create(request["sessionId"] || "default", port: nil)
  end

  defp evaluate(%{"statements" => ""}), do: nil

  defp evaluate(%{"sessionId" => session_id} = request) when is_binary(session_id) do
    # Snippets on a Lepiter page need bindings to persist between them,
    # so these go to the per-page Eval.
    eval = EvalRegistry.get_or_create(session_id, port: nil)
    Eval.eval(eval, request["statements"], request["commandId"])
  end

  defp evaluate(request) do
    # No session means no per-page bindings to keep; each request runs
    # in the connection's task, which is the isolation a per-request
    # process gives.  `port: nil` -- the reply is the only route back.
    Eval.eval_stateless_sync(request["statements"], request["commandId"], nil)
  end
end
