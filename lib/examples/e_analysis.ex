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
end
