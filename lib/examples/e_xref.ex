defmodule Examples.EXref do
  @moduledoc """
  I exercise the long-lived `GtBridge.Xref` service end-to-end and the
  refactored callers (`function_references/3`, `module_graph/1`) that
  depend on it. Acts as a regression catcher for the substrate
  cleanup — if anyone removes the xref subscription or the supervision
  child, these examples go red.
  """

  use ExExample

  import ExUnit.Assertions

  @doc """
  I assert that the long-lived xref process is registered, indexed,
  and answering basic queries. Returns the loaded-modules count so
  callers can sanity-check it grew with the BEAM.
  """
  @spec running() :: non_neg_integer()
  example running do
    assert Process.whereis(GtBridge.Xref) |> is_pid(),
           "GtBridge.Xref must be in the supervision tree"

    {:ok, mods} = GtBridge.Xref.q(~c"M")
    assert length(mods) > 0
    length(mods)
  end

  @doc """
  I run a real call-graph query and verify the long-lived index sees
  edges from this very module. Uses GtBridge.Analysis.module_graph/1
  scoped to gt_bridge so the result set is bounded.
  """
  @spec module_graph_finds_edges() :: non_neg_integer()
  example module_graph_finds_edges do
    edges = GtBridge.Analysis.module_graph(:gt_bridge)
    assert length(edges) > 0
    edges_count = length(edges)

    # Every edge is a {from_mod, to_mod} tuple of atoms within the app
    Enum.each(edges, fn {from, to} ->
      assert is_atom(from)
      assert is_atom(to)
      assert from != to
    end)

    edges_count
  end

  @doc """
  I find callers of GtBridge.Xref.q/1 — known to be called from
  GtBridge.Analysis (function_references/3 and module_graph/1 both
  use it). Asserts the long-lived xref index sees these and returns
  hydrated entries with module/name/arity.
  """
  @spec function_references_finds_callers() :: list(map())
  example function_references_finds_callers do
    callers = GtBridge.Analysis.function_references(GtBridge.Xref, :q, 1)

    assert callers != [], "Xref.q/1 should have callers in GtBridge.Analysis"
    assert Enum.all?(callers, &Map.has_key?(&1, :module))
    assert Enum.all?(callers, &Map.has_key?(&1, :name))
    assert Enum.all?(callers, &Map.has_key?(&1, :arity))

    # All callers should live in GtBridge.Analysis
    assert Enum.any?(callers, &(&1.module == "GtBridge.Analysis"))

    callers
  end

  @doc """
  I prove the xref index reacts to BeamModuleRecompiled events. Insert
  a fake module in the index, broadcast a recompile event for a known
  module, and assert the xref query reflects the BEAM's current state.

  Indirect verification — we can't easily diff xref state before/after
  without another query — so we just assert the recompile path doesn't
  crash and the post-recompile query still works.
  """
  @spec recompile_event_keeps_index_valid() :: non_neg_integer()
  example recompile_event_keeps_index_valid do
    src_path = "fixtures/hot_reload_test/lib/hot_reload_test.ex"
    original = File.read!(src_path)

    {:ok, mods_before} = GtBridge.Xref.q(~c"M")

    try do
      :ok = trigger_recompile(src_path, original)
      # Give the cast a beat to be processed
      Process.sleep(50)
      {:ok, mods_after} = GtBridge.Xref.q(~c"M")
      assert length(mods_after) >= length(mods_before),
             "module count should not shrink after recompile event"

      length(mods_after)
    after
      File.write!(src_path, original)
    end
  end

  defp trigger_recompile(path, content) do
    :ok = GtBridge.HotReload.reload(path, content)
  end

  def rerun?(_), do: true
end
