defmodule GtBridge.Views do
  @moduledoc """
  I hold views for various types, please query me to find out views you are interested in.
  """
  use GenServer
  use TypedStruct

  typedstruct do
    field(:mapping, %{atom() => MapSet.t(code())}, default: Map.new())
  end

  @type options() :: {:name, GenServer.name()}
  @type code() :: {module(), function_name :: atom()}

  @spec start_link([options()]) :: GenServer.on_start()
  def start_link(init_args) do
    name = Keyword.get(init_args, :name, nil)
    GenServer.start_link(__MODULE__, init_args, name: name)
  end

  @impl true
  def init(_init_args) do
    {:ok, %__MODULE__{}}
  end

  ############################################################
  #                      Public RPC API                      #
  ############################################################

  @spec delete(GenServer.server(), atom(), code()) :: :ok
  def delete(server, module, code) do
    GenServer.cast(server, {:delete, module, code})
  end

  @spec add(GenServer.server(), atom(), code()) :: :ok
  def add(server, module, code) do
    GenServer.cast(server, {:add, module, code})
  end

  @spec lookup(GenServer.server(), atom()) :: MapSet.t(code())
  def lookup(server, module) do
    GenServer.call(server, {:lookup, module})
  end

  ############################################################
  #                    Genserver Behavior                    #
  ############################################################

  @impl true
  def handle_call({:lookup, module}, _from, state) do
    {:reply, handle_lookup(module, state), state}
  end

  @impl true
  def handle_cast({:add, module, code}, state) do
    {:noreply, handle_add_view(module, code, state)}
  end

  def handle_cast({:delete, module, code}, state) do
    {:noreply, handle_delete_view(module, code, state)}
  end

  ############################################################
  #                 Genserver Implementation                 #
  ############################################################

  @spec handle_add_view(atom(), code(), t()) :: t()
  def handle_add_view(module, code, state = %__MODULE__{}) do
    new_mapping =
      Map.update(state.mapping, module, MapSet.new([code]), &MapSet.put(&1, code))

    %__MODULE__{state | mapping: new_mapping}
  end

  @spec handle_delete_view(atom(), code(), t()) :: t()
  def handle_delete_view(module, code, state = %__MODULE__{}) do
    new_mapping =
      Map.update(state.mapping, module, MapSet.new([]), &MapSet.delete(&1, code))

    %__MODULE__{state | mapping: new_mapping}
  end

  @spec handle_lookup(atom(), t()) :: MapSet.t(code())
  def handle_lookup(module, %__MODULE__{mapping: m}) do
    Map.get(m, module, MapSet.new())
  end
end
