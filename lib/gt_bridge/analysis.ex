# credo:disable-for-this-file
defmodule GtBridge.Analysis do
  @moduledoc """
  I provide static analysis data for GT visualization.

  I use `:xref` to extract module-level call graphs from compiled
  BEAM files and `GtBridge.Beam.docs/1` for documentation coverage.
  I return raw data — GT builds the views.

  Sibling modules cover related subsystems split out from this one:
  `GtBridge.HotReload` (hot_reload + compile dep edges),
  `GtBridge.DepGraph` (app dep trees + root_apps),
  `GtBridge.Mnesia` (table introspection),
  `GtBridge.Supervision` (process tree), and
  `GtBridge.Eval.Preamble` (editor session import-loading).
  """

  alias GtBridge.Analysis.Source

  # The pure source-text half lives in Analysis.Source; these names
  # stay here because GT eval strings and Elixir callers address them
  # as GtBridge.Analysis.
  alias GtBridge.Analysis.CallSites
  alias GtBridge.Analysis.Graph
  alias GtBridge.Analysis.LoadedModules

  defdelegate module_graph(app), to: Graph
  defdelegate callees(mod, app), to: Graph
  defdelegate callers(mod, app), to: Graph
  defdelegate implementors(name, arity \\ nil), to: Graph
  defdelegate function_references(mod, name, arity \\ nil), to: Graph

  defdelegate call_sites(source, context_module \\ nil), to: CallSites
  defdelegate resolve_alias(context_module, alias_name), to: CallSites
  defdelegate module_aliases(mod), to: CallSites
  defdelegate module_imports(mod), to: CallSites
  defdelegate function_in_module?(mod, name), to: CallSites
  defdelegate modules_loaded?(names), to: CallSites

  defdelegate functions_in_source(source), to: Source
  defdelegate modules_in_source(source), to: Source
  defdelegate module_in_source(source), to: Source
  defdelegate swap_functions(source, module, name_a, arity_a, name_b, arity_b), to: Source
  defdelegate replace_function(source, module, name, arity, new_text), to: Source
  defdelegate append_function(source, module, new_text), to: Source

  @doc """
  I return aggregate stats across all loaded applications.

  Returns a map with `:apps`, `:modules`, `:functions`,
  `:with_docs`, and `:with_source` counts.
  """
  @spec system_stats() :: map()
  def system_stats do
    zero = %{modules: 0, functions: 0, with_docs: 0, with_source: 0}

    LoadedModules.all_modules()
    |> Enum.reduce(zero, fn mod, acc ->
      {fun_count, has_doc} = module_doc_info(mod)

      merge_counts(acc, %{
        modules: 1,
        functions: fun_count,
        with_docs: if(has_doc, do: 1, else: 0),
        with_source: if(has_source?(mod), do: 1, else: 0)
      })
    end)
    |> Map.put(:apps, length(Application.loaded_applications()))
  end

  defp merge_counts(a, b) do
    Map.merge(a, b, fn _k, v1, v2 -> v1 + v2 end)
  end

  @doc """
  I return documentation coverage grouped by application.

  Each entry has `:app` (string name) and `:modules` (list of
  `%{name: String.t(), has_doc: boolean()}`). Used by the GT-side
  doc coverage heatmap.
  """
  @spec system_doc_coverage() :: [map()]
  def system_doc_coverage do
    Application.loaded_applications()
    |> Enum.map(fn {app, _, _} ->
      mods =
        LoadedModules.modules_for_app(app)
        |> Enum.map(fn mod ->
          %{name: inspect(mod), has_doc: module_has_doc?(mod)}
        end)

      %{app: Atom.to_string(app), modules: mods}
    end)
    |> Enum.sort_by(& &1.app)
  end

  @doc """
  I return per-module doc coverage with function-level detail for an app.

  Each entry has `:module`, `:has_mod_doc`, and `:functions` (list of
  `%{name: String.t(), has_doc: boolean()}`).
  """
  @spec app_doc_coverage(atom()) :: [map()]
  def app_doc_coverage(app) do
    LoadedModules.modules_for_app(app)
    |> Enum.map(fn mod ->
      %{module: inspect(mod), has_mod_doc: module_has_doc?(mod), functions: fun_docs(mod)}
    end)
    |> Enum.sort_by(& &1.module)
  end

  defp fun_docs(mod) do
    case GtBridge.Beam.docs(mod) do
      {:docs_v1, _, _, _, _, _, docs} ->
        Enum.map(docs, fn {{kind, name, arity}, _, _, doc, _} ->
          has_doc = kind == :function and doc != :none and doc != :hidden
          %{name: Atom.to_string(name), arity: arity, has_doc: has_doc}
        end)

      _ ->
        []
    end
  end

  @doc """
  I return all function definitions with complete line ranges.

  Each entry includes `:start` (extended back to include @doc/@spec),
  `:end_line`, `:name`, `:arity`, `:kind`, `:sig`, and `:source`
  (the source text for that function including annotations).

  AST entries are merged with runtime exports from `__info__(:functions)`
  so macro-generated functions (e.g. `defview`, `defstruct` field
  accessors, etc.) are visible. Runtime-only entries get default
  `start: 0`, `end_line: 0`, `kind: :def`, and a placeholder source.

  Type rows come from the source alone: a module with no readable
  source (an OTP beam compiled elsewhere) lists only its exported
  functions.
  """
  @spec all_functions(module()) :: [map()]
  def all_functions(mod) do
    # safe_exported_functions / fetch_specs return empty when `mod` isn't
    # loaded.  After Mix purges a module, the .beam may still be on disk;
    # ensure_loaded reloads it so we get the full red (runtime-only)
    # annotations back.
    Code.ensure_loaded(mod)

    ast_entries =
      GtBridge.Resolve.with_source(mod, [], fn source ->
        Source.module_source_entries(source, inspect(mod))
      end)

    ast_keys = ast_entries |> Enum.map(&{&1.name, &1.arity}) |> MapSet.new()

    specs = GtBridge.Beam.specs_by_arity(mod)

    runtime_extra =
      for {n, a} <- GtBridge.Beam.info(mod, :functions),
          name_str = Atom.to_string(n),
          # Skip __struct__, __info__, __views__, etc. — internal/macro
          # plumbing the user doesn't want in their function list.
          not String.starts_with?(name_str, "__"),
          not MapSet.member?(ast_keys, {name_str, a}) do
        GtBridge.Beam.runtime_stub(name_str, a, Map.get(specs, {n, a}))
      end

    # Place runtime entries that share a name with an AST entry
    # (default-arg siblings — e.g. `def foo(a, b \\ 3)` generates
    # foo/1 alongside the AST's foo/2) immediately above the first
    # AST entry with that name, sorted by arity within the group.
    # True orphan runtime entries (no AST counterpart, like BIFs and
    # macro-only modules) keep their place at the end.
    ast_names = ast_entries |> Enum.map(& &1.name) |> MapSet.new()

    {siblings, orphans} =
      Enum.split_with(runtime_extra, fn f -> MapSet.member?(ast_names, f.name) end)

    siblings_by_name = Enum.group_by(siblings, & &1.name)

    {grouped, _} =
      ast_entries
      |> Enum.sort_by(& &1.start)
      |> Enum.flat_map_reduce(MapSet.new(), fn entry, seen ->
        if MapSet.member?(seen, entry.name) do
          {[entry], seen}
        else
          sibs = siblings_by_name |> Map.get(entry.name, []) |> Enum.sort_by(& &1.arity)
          {sibs ++ [entry], MapSet.put(seen, entry.name)}
        end
      end)

    grouped ++ orphans
  end

  @doc """
  I answer whether the Functions view should show a tab for `mod`, without
  building or serializing the full function list.

  A public (non-`__`) function guarantees `all_functions/1` is non-empty:
  its runtime-export branch reads the same `__info__(:functions)`, so any
  such function ends up in the result. That check settles the common
  module in ~1ms. Only when there's no public function do I fall back to
  the source-parsing `all_functions/1`, which also finds defp-only,
  macro-only, and struct modules. So the answer is identical to
  `all_functions(mod) != []` — just cheaper for the common case.
  """
  @spec has_functions?(module()) :: boolean()
  def has_functions?(mod) do
    Code.ensure_loaded(mod)
    has_public_function?(mod) or all_functions(mod) != []
  rescue
    _ -> false
  end

  defp has_public_function?(mod) do
    Enum.any?(mod.__info__(:functions), fn {name, _arity} ->
      not String.starts_with?(Atom.to_string(name), "__")
    end)
  end

  @doc "I return system info for the Overview view."
  @spec system_info() :: map()
  def system_info do
    %{
      node: Node.self() |> Atom.to_string(),
      otp: System.otp_release(),
      elixir: System.version(),
      cwd: File.cwd!(),
      schedulers: System.schedulers_online(),
      processes: length(Process.list()),
      memory_mb: div(:erlang.memory(:total), 1_048_576)
    }
  end

  @doc "I return per-module metadata for an application."
  @spec module_details(atom()) :: [map()]
  def module_details(app) do
    LoadedModules.modules_for_app(app)
    |> Enum.map(fn mod ->
      name = inspect(mod)
      is_elixir = String.starts_with?(name, "Elixir.") or String.contains?(name, ".")
      {fun_count, has_doc} = module_doc_info(mod)

      %{
        name: name,
        elixir: is_elixir,
        functions: fun_count,
        has_doc: has_doc,
        source: has_source?(mod)
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  @spec all_module_names() :: [String.t()]
  defp all_module_names do
    GtBridge.Analysis.LoadedModules.all_names() |> Enum.sort()
  end

  @doc "I return module names matching a substring query, limited to `max` results."
  @spec search_modules(String.t(), pos_integer()) :: [String.t()]
  def search_modules(query, max \\ 30) do
    q = String.downcase(query)

    all_module_names()
    |> Enum.filter(&String.contains?(String.downcase(&1), q))
    |> Enum.take(max)
  end

  @doc "I return application names matching a substring query."
  @spec search_apps(String.t(), pos_integer()) :: [String.t()]
  def search_apps(query, max \\ 30) do
    q = String.downcase(query)

    Application.loaded_applications()
    |> Enum.map(fn {app, _, _} -> Atom.to_string(app) end)
    |> Enum.sort()
    |> Enum.filter(&String.contains?(&1, q))
    |> Enum.take(max)
  end

  @doc "I return exported functions matching a query within an app."
  @spec search_functions(atom(), String.t(), pos_integer()) :: [map()]
  def search_functions(app, query, max \\ 30) do
    q = String.downcase(query)

    LoadedModules.modules_for_app(app)
    |> Enum.flat_map(fn mod ->
      mod_name = inspect(mod)

      exported_functions(mod)
      |> Enum.map(fn f -> Map.put(f, :module, mod_name) end)
    end)
    |> Enum.filter(fn f ->
      String.contains?(String.downcase(f.name), q) or
        String.contains?(String.downcase(f.module), q)
    end)
    |> Enum.sort_by(&"#{&1.module}.#{&1.name}/#{&1.arity}")
    |> Enum.take(max)
  end

  @doc "I return exported functions for a module (works for both Elixir and Erlang)."
  @spec exported_functions(module()) :: [map()]
  def exported_functions(mod) do
    funs =
      if function_exported?(mod, :__info__, 1) do
        GtBridge.Beam.info(mod, :functions)
      else
        try do
          mod.module_info(:exports)
        rescue
          _ in [UndefinedFunctionError, ArgumentError] -> []
        end
      end

    funs
    |> Enum.reject(fn {name, _} -> String.starts_with?(Atom.to_string(name), "__") end)
    |> Enum.sort()
    |> Enum.map(fn {name, arity} ->
      %{name: Atom.to_string(name), arity: arity}
    end)
  end

  @doc "I return example dependency data for a module that uses ExExample."
  @spec example_deps(module()) :: [{String.t(), [String.t()]}]
  def example_deps(mod) do
    if function_exported?(mod, :__examples__, 0) do
      examples = mod.__examples__()
      example_names = Keyword.keys(examples) |> MapSet.new()

      Enum.map(examples, fn {name, calls} ->
        deps =
          calls
          |> Enum.filter(fn {{m, _}, _} -> m == mod end)
          |> Enum.map(fn {{_, fun}, _} -> fun end)
          |> Enum.filter(&(&1 in example_names))
          |> Enum.uniq()

        {Atom.to_string(name), Enum.map(deps, &Atom.to_string/1)}
      end)
    else
      []
    end
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  defp module_doc_info(mod) do
    try do
      case GtBridge.Beam.docs(mod) do
        {:docs_v1, _, _, _, %{"en" => d}, _, docs} when d != "" -> {length(docs), true}
        {:docs_v1, _, _, _, _, _, docs} -> {length(docs), false}
        _ -> {0, false}
      end
    rescue
      _ in [UndefinedFunctionError, ArgumentError] -> {0, false}
    end
  end

  defp module_has_doc?(mod), do: module_doc_info(mod) |> elem(1)

  # Direct module_info call instead of GtBridge.Resolve.source_file —
  # source_file goes through Code.ensure_loaded?/1, which actively
  # *loads* every module it's called on via the OTP code server.
  # system_stats/module_details iterate every module in every loaded
  # app (~2000), and the ~120 normally-unloaded ones turn into ~5–10s
  # of code-server-serialized loads. module_info is fast for already-
  # loaded modules and raises (caught here) for the rest.
  defp has_source?(mod) do
    try do
      mod.module_info(:compile)[:source] != nil
    rescue
      _ in [UndefinedFunctionError, ArgumentError] -> false
    end
  end
end
