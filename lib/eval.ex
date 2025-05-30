defmodule Eval do
  use GenServer
  use TypedStruct

  typedstruct do
    field(:bindings, Code.binding())
  end

  def start_link(init_args) do
    name = Keyword.get(init_args, :name, nil)
    GenServer.start_link(__MODULE__, init_args, name: name)
  end

  @impl true
  def init(_init_arg) do
    {:ok, %__MODULE__{bindings: []}}
  end

  ############################################################
  #                      Public RPC API                      #
  ############################################################

  @spec eval(GenServer.name(), String.t()) :: {:ok, any()}
  def eval(pid, code) do
    GenServer.call(pid, {:eval, code})
  end

  ############################################################
  #                    Genserver Behavior                    #
  ############################################################

  # TODO garbage collect old values in the environment after a while
  @impl true
  def handle_call({:eval, string}, _from, state = %__MODULE__{}) do
    {term, new_bindings} = Code.eval_string(string, state.bindings)
    {:reply, term, %__MODULE__{state | bindings: new_bindings ++ state.bindings}}
  end
end
