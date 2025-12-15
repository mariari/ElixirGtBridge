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
  @spec register(GenServer.server(), any()) :: non_neg_integer() | nil
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

  @doc """
  Resolve an object by ID, returning the object directly (or nil if not found).
  This is the function GT should call when retrieving lazy objects.
  """
  @spec resolve(non_neg_integer()) :: any() | nil
  def resolve(id) do
    case get(id) do
      {:ok, object} -> object
      :error -> nil
    end
  end

  @doc """
  List all attributes (field names) of an object by ID.
  For structs, returns the field names. For maps, returns the keys.
  """
  @spec list_attributes(non_neg_integer()) :: list(atom() | String.t()) | nil
  def list_attributes(id) do
    case get(id) do
      {:ok, %{__struct__: _module} = struct} ->
        struct |> Map.from_struct() |> Map.keys()

      {:ok, map} when is_map(map) ->
        Map.keys(map)

      {:ok, _other} ->
        []

      :error ->
        nil
    end
  end

  @doc """
  Get the value of a specific attribute from an object by ID.
  """
  @spec get_attribute(non_neg_integer(), atom() | String.t()) :: any() | nil
  def get_attribute(id, attribute_name) do
    case get(id) do
      {:ok, %{__struct__: _module} = struct} ->
        # Try as atom first (struct fields are atoms)
        attr_atom =
          if is_binary(attribute_name),
            do: String.to_existing_atom(attribute_name),
            else: attribute_name

        Map.get(struct, attr_atom)

      {:ok, map} when is_map(map) ->
        Map.get(map, attribute_name)

      {:ok, _other} ->
        nil

      :error ->
        nil
    end
  rescue
    # String.to_existing_atom failed
    ArgumentError -> nil
  end

  ############################################################
  #                    Genserver Behavior                    #
  ############################################################

  @impl true
  def handle_call({:register, object}, _from, state) do
    # Don't register primitives - they'll be sent directly
    if is_primitive(object) do
      {:reply, nil, state}
    else
      id = state.next_id
      new_objects = Map.put(state.objects, id, object)
      new_state = %{state | objects: new_objects, next_id: id + 1}
      {:reply, id, new_state}
    end
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

  ############################################################
  #                 Genserver Implementation                 #
  ############################################################

  # Check if object is a primitive that doesn't need registration
  defp is_primitive(obj) when is_nil(obj), do: true
  defp is_primitive(obj) when is_boolean(obj), do: true
  defp is_primitive(obj) when is_integer(obj), do: true
  defp is_primitive(obj) when is_float(obj), do: true
  defp is_primitive(obj) when is_binary(obj), do: true
  defp is_primitive(obj) when is_atom(obj), do: true
  defp is_primitive(_), do: false
end
