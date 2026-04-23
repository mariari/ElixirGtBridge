defmodule Examples.EHotReload do
  @moduledoc """
  I test the hot-reload system end-to-end.

  Each example modifies a real source file, verifies the change
  took effect, then reverts. Running examples leaves no traces.
  """

  use ExExample
  import ExUnit.Assertions

  # Use Resolve as the test subject — it's a simple module
  # that isn't part of the eval/compilation infrastructure.
  @test_module GtBridge.Resolve

  @spec add_function() :: :ok
  example add_function do
    path = @test_module.__info__(:compile)[:source] |> List.to_string()
    {:ok, original} = File.read(path)

    modified =
      String.replace(
        original,
        "\nend\n",
        "\n  def __hot_reload_test__, do: :it_works\nend\n"
      )

    try do
      GtBridge.Analysis.hot_reload(path, modified)
      assert function_exported?(@test_module, :__hot_reload_test__, 0)
      assert @test_module.__hot_reload_test__() == :it_works
      :ok
    after
      GtBridge.Analysis.hot_reload(path, original)
    end
  end

  @spec struct_field_propagates() :: :ok
  example struct_field_propagates do
    path =
      GtBridge.Phlow.Mondrian.__info__(:compile)[:source]
      |> List.to_string()

    {:ok, original} = File.read(path)

    modified =
      String.replace(
        original,
        "field(:layout, atom(), default: :horizontal_tree)\n  end",
        "field(:layout, atom(), default: :horizontal_tree)\n    field(:__test_field__, String.t(), default: \"works\")\n  end"
      )

    try do
      GtBridge.Analysis.hot_reload(path, modified)

      m = GtBridge.Phlow.Builder.mondrian()
      assert Map.has_key?(m, :__test_field__)
      assert m.__test_field__ == "works"
      :ok
    after
      GtBridge.Analysis.hot_reload(path, original)
    end
  end

  @spec beam_persisted() :: :ok
  example beam_persisted do
    path = @test_module.__info__(:compile)[:source] |> List.to_string()
    {:ok, original} = File.read(path)

    modified =
      String.replace(
        original,
        "\nend\n",
        "\n  def __beam_test__, do: :persisted\nend\n"
      )

    try do
      GtBridge.Analysis.hot_reload(path, modified)

      app = Application.get_application(@test_module)
      ebin = Application.app_dir(app, "ebin")
      beam = Path.join(ebin, "Elixir.GtBridge.Resolve.beam")

      assert File.exists?(beam)

      {:ok, {_, [{:exports, exports}]}} =
        :beam_lib.chunks(String.to_charlist(beam), [:exports])

      assert Enum.any?(exports, fn {name, arity} ->
               name == :__beam_test__ and arity == 0
             end)

      :ok
    after
      GtBridge.Analysis.hot_reload(path, original)
    end
  end

  @spec revert_restores_original() :: :ok
  example revert_restores_original do
    path = @test_module.__info__(:compile)[:source] |> List.to_string()
    {:ok, original} = File.read(path)

    modified =
      String.replace(
        original,
        "\nend\n",
        "\n  def __revert_test__, do: :temporary\nend\n"
      )

    GtBridge.Analysis.hot_reload(path, modified)
    assert function_exported?(@test_module, :__revert_test__, 0)

    GtBridge.Analysis.hot_reload(path, original)
    refute function_exported?(@test_module, :__revert_test__, 0)

    # File should match original
    {:ok, current} = File.read(path)
    assert current == original
    :ok
  end
end
