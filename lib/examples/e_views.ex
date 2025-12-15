defmodule Examples.EViews do
  import ExUnit.Assertions

  use TypedStruct
  use GtBridge.View

  alias GtBridge.Phlow.List
  alias GtBridge.Phlow.Text

  typedstruct do
    field(:int, integer(), default: 0)
    field(:name, String.t(), default: "Example")
  end

  @spec empty() :: t()
  def empty() do
    %__MODULE__{}
  end

  @spec with_values(integer(), String.t()) :: t()
  def with_values(int_value, name_value) do
    %__MODULE__{int: int_value, name: name_value}
  end

  ############################################################
  #                           Views                          #
  ############################################################

  @spec int_list_view(t(), GtBridge.Phlow.Builder) :: List.t()
  defview int_list_view(self = %__MODULE__{}, builder) do
    builder.list()
    |> List.priority(1)
    |> List.title("Int listed")
    |> List.items(fn -> [self.int, self.int * 2, self.int * 3] end)
  end

  @spec name_text_view(t(), GtBridge.Phlow.Builder) :: Text.t()
  defview name_text_view(self = %__MODULE__{}, builder) do
    builder.text()
    |> Text.priority(2)
    |> Text.title("Name")
    |> Text.string(fn -> "Name: #{self.name}" end)
  end

  ############################################################
  #                          Examples                        #
  ############################################################

  @spec int_list_view_ref() :: {Examples.EViews, :int_list_view}
  def int_list_view_ref() do
    {__MODULE__, :int_list_view}
  end

  @spec name_text_view_ref() :: {Examples.EViews, :name_text_view}
  def name_text_view_ref() do
    {__MODULE__, :name_text_view}
  end

  @spec empty_view() :: pid()
  def empty_view() do
    {:ok, pid} = GtBridge.Views.start_link([])
    pid
  end

  @spec register_views() :: pid()
  def register_views() do
    ret = empty_view()

    # Register all views from this module
    GtBridge.View.register(__MODULE__, ret)

    views = GtBridge.Views.lookup(ret, __MODULE__)

    # Should have both views registered
    assert MapSet.size(views) == 2
    assert MapSet.member?(views, int_list_view_ref())
    assert MapSet.member?(views, name_text_view_ref())

    ret
  end

  @spec test_get_view_specs() :: :ok
  def test_get_view_specs() do
    server = register_views()
    obj = with_values(42, "Test")

    specs = GtBridge.View.get_view_object(obj, server)

    # Should have 2 view specs
    assert length(specs) == 2

    # Check that they're properly formatted
    Enum.each(specs, fn spec ->
      assert Map.has_key?(spec, :title)
      assert Map.has_key?(spec, :priority)
      assert Map.has_key?(spec, :viewName)
    end)

    :ok
  end
end
