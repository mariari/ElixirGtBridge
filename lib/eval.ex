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
    {:ok, %__MODULE__{bindings: [], port: port}}
  end

  ############################################################
  #                      Public RPC API                      #
  ############################################################

  @spec eval(GenServer.name(), String.t(), String.t()) :: {:ok, any()}
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
      |> Code.eval_string([command_id: command_id, port: state.port] ++ state.bindings)

    {:reply, term, %__MODULE__{state | bindings: new_bindings ++ state.bindings}}
  end

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
