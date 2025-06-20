defmodule Eval do
  use GenServer
  use TypedStruct

  typedstruct do
    field(:bindings, Code.binding())
    field(:port, non_neg_integer(), default: nil)
  end

  def start_link(init_args) do
    name = Keyword.get(init_args, :name, nil)
    GenServer.start_link(__MODULE__, init_args, name: name)
  end

  @impl true
  def init(init_args) do
    port = Keyword.get(init_args, :port, nil)
    default_bindings = if port, do: [port: port], else: []
    {:ok, %__MODULE__{bindings: default_bindings, port: port}}
  end

  ############################################################
  #                      Public RPC API                      #
  ############################################################

  @spec eval(GenServer.server(), String.t(), String.t() | nil) :: any()
  def eval(pid, code, command_id) do
    GenServer.call(pid, {:eval, code, command_id})
  end

  ############################################################
  #                    Genserver Behavior                    #
  ############################################################

  # TODO garbage collect old values in the environment after a while
  @impl true
  def handle_call({:eval, string, command_id}, _from, state = %__MODULE__{}) do
    {term, new_bindings} =
      string
      |> String.replace("\r", "\n")
      |> Code.eval_string(state.bindings ++ [command_id: command_id])

    # Remove duplicated keys and ports
    unique_keys = Keyword.merge(state.bindings, Keyword.delete(new_bindings, :port))

    {:reply, term, %__MODULE__{state | bindings: unique_keys}}
  end

  @spec notify(term(), String.t(), pos_integer()) :: term()
  def notify(obj, id, port) do
    {:ok, val} = GtBridge.Serializer.to_json(obj)

    data = %{
      type: "EVAL",
      id: id,
      value: val,
      __sync: "_"
    }

    Req.post!("http://localhost:" <> to_string(port) <> "/EVAL", json: data)
    obj
  end
end
