defmodule Examples.EHotReload do
  @moduledoc """
  I test the hot-reload system end-to-end against a real dependency.

  HotReloadTest is a path dep under fixtures/ with a struct (Config)
  and a struct caller (Builder). Examples modify its source, verify
  the change took effect, then revert. Running examples leaves no
  traces.

  All mutation examples go through `with_reload/3` which handles
  the write-compile-revert cycle. Each example only specifies what
  to change and what to observe.
  """

  use ExExample
  import ExUnit.Assertions

  def rerun?(_), do: true

  # I return {path, original_content} for HotReloadTest's root module.
  @spec resolve_source() :: {String.t(), String.t()}
  example resolve_source do
    {path, original} = source_for(HotReloadTest)
    assert String.contains?(original, "defmodule HotReloadTest")
    {path, original}
  end

  # I add a function to a dep and return the module's updated
  # export list.
  @spec add_function() :: [{atom(), non_neg_integer()}]
  example add_function do
    with_reload(HotReloadTest, &inject_before_end(&1, "def __test__, do: :it_works"), fn ->
      # apply/3 because __test__/0 is injected at runtime — static
      # analysis can't see it, so a direct call would warn.
      assert apply(HotReloadTest, :__test__, []) == :it_works
      HotReloadTest.__info__(:functions)
    end)
  end

  # I modify hello's return value and return the formatted source
  # from disk.
  @spec modify_function() :: String.t()
  example modify_function do
    {path, _} = source_for(HotReloadTest)

    with_reload(HotReloadTest, &String.replace(&1, "do: :world", "do: :modified"), fn ->
      # apply/3 because the static type of `HotReloadTest.hello/0`
      # is `:world` (its compile-time definition); the test mutates
      # it to return `:modified`, and a direct call would trigger
      # the `:world == :modified` disjoint-types warning.
      assert apply(HotReloadTest, :hello, []) == :modified
      File.read!(path)
    end)
  end

  # I add a new field to Config, then add an accessor to Builder
  # that uses it. Proves cross-module hot-reload works when
  # changes depend on each other.
  @spec new_field_propagates() :: String.t()
  example new_field_propagates do
    with_reload(
      HotReloadTest.Config,
      &String.replace(&1, "value: 0", ~s(value: 0, extra: "propagated")),
      fn ->
        with_reload(
          HotReloadTest.Builder,
          &inject_before_end(&1, ~s(def extra, do: %Config{}.extra)),
          fn ->
            # apply/3: `extra/0` is injected at runtime via the
            # outer with_reload's transform.
            result = apply(HotReloadTest.Builder, :extra, [])
            assert result == "propagated"
            result
          end
        )
      end
    )
  end

  # I add a function and return the beam file's export list —
  # proving beams are persisted to ebin.
  @spec beam_persisted() :: [{atom(), non_neg_integer()}]
  example beam_persisted do
    with_reload(HotReloadTest, &inject_before_end(&1, "def __beam__, do: :ok"), fn ->
      exports = beam_exports(HotReloadTest)
      assert {:__beam__, 0} in exports
      exports
    end)
  end

  # I hot-reload a standalone file with no application registration
  # and return its module info.
  @spec standalone_module() :: keyword()
  example standalone_module do
    mod = :"Elixir.HotReloadStandaloneTest"
    path = Path.join(System.tmp_dir!(), "hot_reload_standalone_test.ex")

    source =
      "defmodule HotReloadStandaloneTest do\n  def value, do: :standalone\nend\n"

    try do
      GtBridge.HotReload.reload(path, source)
      assert apply(mod, :value, []) == :standalone
      assert Application.get_application(mod) == nil
      apply(mod, :module_info, [])
    after
      File.rm(path)
      :code.purge(mod)
      :code.delete(mod)
    end
  end

  # I verify revert restores source, beam, and module exports.
  # Returns exports after revert.
  @spec revert_clean() :: [{atom(), non_neg_integer()}]
  example revert_clean do
    {path, original} = source_for(HotReloadTest)
    modified = inject_before_end(original, "def __revert__, do: :tmp")

    GtBridge.HotReload.reload(path, modified)
    assert function_exported?(HotReloadTest, :__revert__, 0)

    GtBridge.HotReload.reload(path, original)
    refute function_exported?(HotReloadTest, :__revert__, 0)

    assert File.read!(path) == original
    exports = beam_exports(HotReloadTest)
    refute {:__revert__, 0} in exports
    exports
  end

  ############################################################
  #                         Helpers                          #
  ############################################################

  # I handle the write-compile-revert cycle. `transform` receives
  # the original source and returns the modified version. `observe`
  # runs after hot-reload and its return value becomes the example
  # result. Revert is automatic.
  defp with_reload(mod, transform, observe) do
    {path, original} = source_for(mod)

    try do
      GtBridge.HotReload.reload(path, transform.(original))
      observe.()
    after
      GtBridge.HotReload.reload(path, original)
    end
  end

  defp source_for(mod) do
    path = GtBridge.Resolve.source_file(mod)
    {:ok, content} = File.read(path)
    {path, content}
  end

  defp inject_before_end(source, definition) do
    String.replace(source, "\nend\n", "\n  #{definition}\nend\n")
  end

  defp beam_exports(mod) do
    app = Application.get_application(mod)
    beam = Path.join(Application.app_dir(app, "ebin"), "#{mod}.beam")

    {:ok, {_, [{:exports, exports}]}} =
      :beam_lib.chunks(String.to_charlist(beam), [:exports])

    exports
  end
end
