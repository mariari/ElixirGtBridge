defmodule Examples.EAnalysis.EnforcedStruct do
  @moduledoc false
  use TypedStruct

  # typedstruct WITH an option — the case that used to lose its `t` type.
  typedstruct enforce: true do
    field(:id, atom(), enforce: true)
  end
end

defmodule Examples.EAnalysis do
  @moduledoc """
  I am examples for GtBridge.Analysis, the static analysis module.
  """

  use ExExample

  import ExUnit.Assertions

  alias GtBridge.Analysis

  def rerun?(_), do: true

  ############################################################
  #                    Module Graph Examples                  #
  ############################################################

  @spec module_graph() :: [Analysis.edge()]
  example module_graph do
    edges = Analysis.module_graph(:gt_bridge)

    assert length(edges) > 0
    assert Enum.all?(edges, fn {from, to} -> is_atom(from) and is_atom(to) end)
    # Eval calls ObjectRegistry
    assert {GtBridge.Eval, GtBridge.ObjectRegistry} in edges

    edges
  end

  @spec callees_of_eval() :: [module()]
  example callees_of_eval do
    mods = Analysis.callees(GtBridge.Eval, :gt_bridge)

    assert GtBridge.ObjectRegistry in mods
    assert GtBridge.Eval not in mods

    mods
  end

  @spec callers_of_serializer() :: [module()]
  example callers_of_serializer do
    mods = Analysis.callers(GtBridge.Serializer, :gt_bridge)

    assert length(mods) > 0

    mods
  end

  ############################################################
  #                 Supervision Tree Examples                 #
  ############################################################

  @spec supervision_tree() :: map()
  example supervision_tree do
    pid = Process.whereis(GtBridge.Supervisor)
    tree = GtBridge.Supervision.tree(pid)

    assert tree.name == "GtBridge.Supervisor"
    assert tree.supervisor == true
    assert length(tree.children) > 0

    tree
  end

  ############################################################
  #                  System-Wide Examples                     #
  ############################################################

  @spec system_stats() :: map()
  example system_stats do
    stats = Analysis.system_stats()

    assert stats.apps > 0
    assert stats.modules > 0
    assert stats.with_docs >= 0

    stats
  end

  @spec system_doc_coverage() :: [map()]
  example system_doc_coverage do
    coverage = Analysis.system_doc_coverage()

    assert length(coverage) > 0
    assert Enum.all?(coverage, fn c -> is_binary(c.app) end)
    gt = Enum.find(coverage, fn c -> c.app == "gt_bridge" end)
    assert gt != nil
    assert length(gt.modules) > 0

    coverage
  end

  ############################################################
  #                  New Function Examples                    #
  ############################################################

  @spec system_info() :: map()
  example system_info do
    info = Analysis.system_info()

    assert is_binary(info.node)
    assert is_binary(info.elixir)
    assert info.schedulers > 0
    assert info.memory_mb > 0

    info
  end

  @spec module_details() :: [map()]
  example module_details do
    details = Analysis.module_details(:gt_bridge)

    assert length(details) > 0
    eval = Enum.find(details, fn d -> d.name == "GtBridge.Eval" end)
    assert eval != nil
    assert eval.has_doc == true
    assert eval.functions > 0

    details
  end

  @spec root_apps() :: [atom()]
  example root_apps do
    roots = GtBridge.DepGraph.root_apps()

    assert length(roots) > 0
    assert is_atom(hd(roots))

    roots
  end

  @spec exported_functions() :: [map()]
  example exported_functions do
    fns = Analysis.exported_functions(GtBridge.Eval)

    assert length(fns) > 0
    assert Enum.any?(fns, fn f -> f.name == "eval" end)

    fns
  end

  @spec exported_functions_erlang() :: [map()]
  example exported_functions_erlang do
    fns = Analysis.exported_functions(:erlang)

    assert length(fns) > 0
    assert Enum.any?(fns, fn f -> f.name == "node" end)

    fns
  end

  @spec example_deps() :: [{String.t(), [String.t()]}]
  example example_deps do
    deps = Analysis.example_deps(Examples.EEval)

    assert length(deps) > 0
    {name, _} = hd(deps)
    assert is_binary(name)

    deps
  end

  @spec app_dep_tree() :: map()
  example app_dep_tree do
    tree = GtBridge.DepGraph.app_dep_tree(:gt_bridge)

    assert tree.name == "gt_bridge"
    assert length(tree.children) > 0

    tree
  end

  @spec app_reverse_dep_tree() :: map()
  example app_reverse_dep_tree do
    tree = GtBridge.DepGraph.app_reverse_dep_tree(:gt_bridge)

    assert tree.name == "gt_bridge"

    tree
  end

  @spec mnesia_tables() :: [map()]
  example mnesia_tables do
    tables =
      try do
        GtBridge.Mnesia.tables()
      rescue
        _ -> []
      end

    assert is_list(tables)

    tables
  end

  ############################################################
  #                  Implementors Examples                    #
  ############################################################

  @spec implementors_of_start_link() :: [map()]
  example implementors_of_start_link do
    results = Analysis.implementors(:start_link)
    assert length(results) > 0
    assert Enum.all?(results, &Map.has_key?(&1, :module))
    assert Enum.all?(results, &(&1.name == "start_link"))
    results
  end

  @spec implementors_with_arity() :: [map()]
  example implementors_with_arity do
    results = Analysis.implementors(:start_link, 1)
    assert length(results) > 0
    assert Enum.all?(results, &(&1.arity == 1))
    results
  end

  @spec implementors_required_keys() :: [map()]
  example implementors_required_keys do
    required = [:name, :arity, :module, :kind, :start, :end_line, :sig, :source]
    results = Analysis.implementors(:new, nil)

    assert length(results) > 0

    for entry <- results, key <- required do
      assert Map.has_key?(entry, key), "missing #{inspect(key)} in #{inspect(entry)}"
    end

    results
  end

  ############################################################
  #              Function References Examples                 #
  ############################################################

  @spec references_to_source_file() :: [map()]
  example references_to_source_file do
    results = Analysis.function_references(GtBridge.Resolve, :source_file, 1)
    assert length(results) > 0
    assert Enum.all?(results, &Map.has_key?(&1, :module))
    results
  end

  ############################################################
  #                  Call Site Examples                       #
  ############################################################

  @spec call_sites_simple() :: [map()]
  example call_sites_simple do
    source = ~s'''
    defmodule Example do
      def run do
        Enum.map([1, 2], &inspect/1)
        String.trim(" hello ")
      end
    end
    '''

    sites = Analysis.call_sites(source)
    modules = Enum.map(sites, & &1.target_module)
    assert "Enum" in modules
    assert "String" in modules
    assert Enum.all?(sites, &Map.has_key?(&1, :line))
    sites
  end

  @spec modules_loaded_batch_query() :: %{String.t() => boolean()}
  example modules_loaded_batch_query do
    result =
      Analysis.modules_loaded?(["GtBridge.Eval", "Enum", "TotallyNotAModuleXYZ"])

    assert result["GtBridge.Eval"] == true
    assert result["Enum"] == true
    assert result["TotallyNotAModuleXYZ"] == false
    result
  end

  @doc """
  I define a module outside the bridge's pipeline (bare eval, as iex
  or dynamic codegen would) and verify `sync` enters it into the
  record: the fact is broadcast and the projection picks it up.
  Message-driven - I wait on the broker's own event, no sleeps.
  Returns the names sync announced.
  """
  @spec dynamic_module_discovery() :: [String.t()]
  example dynamic_module_discovery do
    mod = DynDiscoveryProbe
    EventBroker.subscribe_me([%GtBridge.Events.AnyModuleEvent{}])

    try do
      Code.eval_string("defmodule DynDiscoveryProbe do\n  def here, do: :yes\nend")

      announced = Analysis.LoadedModules.sync()
      assert "DynDiscoveryProbe" in announced

      assert_receive %EventBroker.Event{
                       body: %GtBridge.Events.ModuleEvent{kind: :recompiled, mod: ^mod}
                     },
                     5_000

      assert Analysis.LoadedModules.loaded?("DynDiscoveryProbe")
      announced
    after
      EventBroker.unsubscribe_me([%GtBridge.Events.AnyModuleEvent{}])
      GtBridge.HotReload.purge_module(mod)
    end
  end

  @doc """
  I delete a module out-of-band (bare `:code.delete`, not the bridge's
  purge) and verify full reconciliation retracts it as a
  `:source_removed` fact. Not loaded alone is not enough (the BEAM
  loads lazily); gone means not vouched for by any app spec and not
  loadable either. Returns the reconciliation diff.
  """
  @spec out_of_band_removal_retracted() :: %{added: [String.t()], removed: [String.t()]}
  example out_of_band_removal_retracted do
    mod = OutOfBandProbe
    Code.eval_string("defmodule OutOfBandProbe do\n  def gone_soon, do: :yes\nend")
    assert "OutOfBandProbe" in Analysis.LoadedModules.sync()

    EventBroker.subscribe_me([%GtBridge.Events.AnyModuleEvent{}])

    try do
      :code.purge(mod)
      :code.delete(mod)
      assert Analysis.LoadedModules.loaded?("OutOfBandProbe")

      diff = Analysis.LoadedModules.full_sync()
      assert "OutOfBandProbe" in diff.removed

      assert_receive %EventBroker.Event{
                       body: %GtBridge.Events.ModuleEvent{kind: :source_removed, mod: ^mod}
                     },
                     5_000

      refute Analysis.LoadedModules.loaded?("OutOfBandProbe")
      diff
    after
      EventBroker.unsubscribe_me([%GtBridge.Events.AnyModuleEvent{}])
    end
  end

  @spec call_sites_with_aliases() :: [map()]
  example call_sites_with_aliases do
    source = ~s'''
    defmodule Example do
      alias GtBridge.Analysis
      def run, do: Analysis.module_graph(:gt_bridge)
    end
    '''

    sites = Analysis.call_sites(source)
    assert Enum.any?(sites, &(&1.target_module == "GtBridge.Analysis"))
    sites
  end

  # A local `defp` called within the same source resolves even with no
  # context module — nil context used to zero the local set, dropping
  # local calls to the foreign path that (correctly) hides privates.
  @spec call_sites_local_defp_without_context() :: [map()]
  example call_sites_local_defp_without_context do
    source = ~s'''
    defmodule Example do
      defmacro defrel(a, b), do: store(a, b)
      defp store(a, b), do: a + b
    end
    '''

    sites = Analysis.call_sites(source)
    assert Enum.any?(sites, &(&1.function == "store"))
    sites
  end

  # A cross-module public type reference (`.t()`) resolves — type names
  # live in the beam type chunk, not `__info__`, so exports alone missed
  # them.
  @spec call_sites_cross_module_type() :: [map()]
  example call_sites_cross_module_type do
    source = ~s'''
    defmodule Example do
      @type stage :: GtBridge.Events.ModuleEvent.t()
    end
    '''

    sites = Analysis.call_sites(source)

    assert Enum.any?(
             sites,
             &(&1.function == "t" and &1.target_module == "GtBridge.Events.ModuleEvent")
           )

    sites
  end

  ############################################################
  #                  Source Edit Examples                     #
  ############################################################

  @spec swap_functions_keeps_bodies_intact() :: String.t()
  example swap_functions_keeps_bodies_intact do
    # Both wrap :mnesia.transaction(fn -> ... end); drifted line numbers
    # fuse them and leave a dangling `end`. Source-derived ranges can't.
    source = ~s'''
    defmodule AL.Branch do
      @spec stored_head() :: t()
      defp stored_head() do
        {:atomic, branch} =
          :mnesia.transaction(fn ->
            case :mnesia.read(:meta, :head) do
              [{:meta, :head, branch}] -> branch
              [] -> :main
            end
          end)

        %__MODULE__{id: branch}
      end

      @spec main() :: t()
      def main() do
        %__MODULE__{id: :main}
      end
    end
    '''

    swapped = Analysis.swap_functions(source, "AL.Branch", "stored_head", 0, "main", 0)

    # Re-parses cleanly with the two functions reordered and each body whole.
    {:ok, _} = Code.string_to_quoted(swapped)
    entries = Analysis.functions_in_source(swapped)
    assert Enum.map(entries, & &1.name) == ["main", "stored_head"]

    by_name = Map.new(entries, &{&1.name, &1.source})
    assert by_name["main"] =~ "%__MODULE__{id: :main}"
    assert by_name["stored_head"] =~ "%__MODULE__{id: branch}"
    assert by_name["stored_head"] =~ "case :mnesia.read(:meta, :head) do"

    swapped
  end

  @spec replace_function_save_and_delete() :: String.t()
  example replace_function_save_and_delete do
    source = ~s'''
    defmodule M do
      @spec a() :: :ok
      def a do
        if true do
          :ok
        end
      end

      @spec b() :: :ok
      def b, do: :ok
    end
    '''

    edited = Analysis.replace_function(source, "M", "a", 0, "  def a, do: :rewritten")
    {:ok, _} = Code.string_to_quoted(edited)
    assert edited =~ "def a, do: :rewritten"
    refute edited =~ "if true do"
    assert edited =~ "def b, do: :ok"

    # Empty new_text removes the function (the delete path).
    removed = Analysis.replace_function(source, "M", "a", 0, "")
    {:ok, _} = Code.string_to_quoted(removed)
    assert Analysis.functions_in_source(removed) |> Enum.map(& &1.name) == ["b"]

    edited
  end

  @spec append_function_finds_module_end() :: String.t()
  example append_function_finds_module_end do
    # `end # M` has no bare-`end` line, which defeats a findLast-"end" scan;
    # parsing locates the module close, so the new function lands inside it.
    source = "defmodule M do\n  def a, do: 1\nend # M\n"
    appended = Analysis.append_function(source, "M", "  def b, do: 2")

    {:ok, _} = Code.string_to_quoted(appended)
    assert Analysis.functions_in_source(appended) |> Enum.map(& &1.name) == ["a", "b"]

    appended
  end

  @spec typedstruct_with_options_locates_t() :: map()
  example typedstruct_with_options_locates_t do
    # `typedstruct enforce: true do` keeps its block in the same arg list; the
    # locator must still find it, or the `t` type drops to start: 0 and vanishes
    # from the function browser.
    t =
      Analysis.all_functions(Examples.EAnalysis.EnforcedStruct)
      |> Enum.find(&(&1.name == "t" and &1.kind == :type))

    assert t != nil
    assert t.start > 0

    t
  end

  @spec functions_in_source_includes_types() :: [map()]
  example functions_in_source_includes_types do
    # functions_in_source primes the source-written cache; it must carry types
    # or a plain save strips them from the browser until a recompile re-primes.
    source = """
    defmodule M do
      use TypedStruct
      @type id :: atom()
      typedstruct enforce: true do
        field(:id, atom())
      end
      def go, do: :ok
    end
    """

    by_kind = Analysis.functions_in_source(source) |> Enum.group_by(& &1.kind)

    assert Enum.map(by_kind[:type], & &1.name) |> Enum.sort() == ["id", "t"]
    assert "go" in Enum.map(by_kind["def"], & &1.name)

    by_kind
  end
end
