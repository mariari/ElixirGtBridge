defmodule Eval do
  use GenServer

  def start_link(init_args) do
    GenServer.start_link(__MODULE__, init_args)
  end

  @impl true
  def init(init_arg) do
    {:ok, init_arg}
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

  # TODO Handle bindings
  @impl true
  def handle_call({:eval, string}, _from, state) do
    {:reply, Code.eval_string(string), state}
  end
end
