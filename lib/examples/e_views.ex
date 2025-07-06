defmodule Examples.EViews do
  import ExUnit.Assertions

  use TypedStruct
  use GtBridge.View

  typedstruct do
    field(:int, integer(), default: 0)
  end

  @spec empty() :: t()
  def empty() do
    %__MODULE__{}
  end

  ############################################################
  #                           Views                          #
  ############################################################

  @spec some_view(t()) :: any()
  defview some_view(self = %__MODULE__{}) do
    self.int
  end

  ############################################################
  #                          Examples                        #
  ############################################################

  @spec some_view_ref() :: {Examples.EViews, :some_view}
  def some_view_ref() do
    {__MODULE__, :some_view}
  end

  @spec empty_view() :: pid()
  def empty_view() do
    {:ok, pid} = GtBridge.Views.start_link([])
    pid
  end

  @spec add_some_view() :: pid()
  def add_some_view() do
    ret = empty_view()

    GtBridge.Views.add(ret, __MODULE__, some_view_ref())

    views = GtBridge.Views.lookup(ret, __MODULE__)

    assert views == MapSet.new([some_view_ref()])

    all_views_valid(empty(), views)

    ret
  end

  @spec delete_some_view() :: pid()
  def delete_some_view() do
    ret = add_some_view()

    GtBridge.Views.delete(ret, __MODULE__, some_view_ref())
    assert GtBridge.Views.lookup(ret, __MODULE__) == MapSet.new()

    ret
  end

  @spec all_views_valid(any(), MapSet.t((any() -> any()))) :: boolean()
  def all_views_valid(data, views) do
    assert Enum.all?(views, fn {mod, name} -> apply(mod, name, [data]) end)
  end
end
