defmodule GtBridge.ObjectRegistry do
  @moduledoc """
  I am a Registry for objects that are referenced from GT.

  This allows GT to keep references to Elixir objects via IDs,
  and handles cleanup when GT's proxy objects are garbage collected.
  """
  use GenServer

  @doc """
  Start the object registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    {:ok, %{objects: %{}, next_id: 1}}
  end

  ############################################################
  #                      Public RPC API                      #
  ############################################################

  @doc """
  Register an object and return its ID.
  """
  @spec register(GenServer.server(), any()) :: non_neg_integer()
  def register(server \\ __MODULE__, object) do
    GenServer.call(server, {:register, object})
  end

  @doc """
  Get an object by ID.
  """
  @spec get(GenServer.server(), non_neg_integer()) :: {:ok, any()} | :error
  def get(server \\ __MODULE__, id) do
    GenServer.call(server, {:get, id})
  end

  @doc """
  Remove an object by ID (called when GT garbage collects the proxy).
  """
  @spec remove(GenServer.server(), non_neg_integer()) :: :ok
  def remove(server \\ __MODULE__, id) do
    GenServer.cast(server, {:remove, id})
  end

  ############################################################
  #                    Genserver Behavior                    #
  ############################################################

  @impl true
  def handle_call({:register, object}, _from, state) do
    id = state.next_id
    new_objects = Map.put(state.objects, id, object)
    new_state = %{state | objects: new_objects, next_id: id + 1}
    {:reply, id, new_state}
  end

  def handle_call({:get, id}, _from, state) do
    result = Map.fetch(state.objects, id)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:remove, id}, state) do
    new_objects = Map.delete(state.objects, id)
    {:noreply, %{state | objects: new_objects}}
  end
end
