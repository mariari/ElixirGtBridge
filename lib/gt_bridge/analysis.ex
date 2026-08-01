# credo:disable-for-this-file
defmodule GtBridge.Analysis do
  @moduledoc """
  I provide static analysis data for GT visualization.

  I use `:xref` to extract module-level call graphs from compiled
  BEAM files and `Code.fetch_docs/1` for documentation coverage.
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
  defdelegate functions_in_source(source), to: Source
  defdelegate modules_in_source(source), to: Source
  defdelegate module_in_source(source), to: Source
  defdelegate swap_functions(source, module, name_a, arity_a, name_b, arity_b), to: Source
  defdelegate replace_function(source, module, name, arity, new_text), to: Source
  defdelegate append_function(source, module, new_text), to: Source

  @type edge :: {module(), module()}

  @doc """
  I return module-level call edges for an application.

  Each edge `{from, to}` means `from` contains a call to a function
  in `to`. Self-edges are excluded. Only modules whose BEAM files
  are on the code path are analyzed.
  """
  @spec module_graph(atom()) :: [edge()]
  def module_graph(app) do
    app_mods = MapSet.new(modules(app))

    case GtBridge.Xref.q(~c"E") do
      {:ok, edges} ->
        for {{from, _, _}, {to, _, _}} <- edges,
            MapSet.member?(app_mods, from),
            MapSet.member?(app_mods, to),
            from != to,
            uniq: true,
            do: {from, to}

      _ ->
        []
    end
  end

  @doc "I return the modules that `mod` calls within `app`."
  @spec callees(module(), atom()) :: [module()]
  def callees(mod, app) do
    for {^mod, to} <- module_graph(app), do: to
  end

  @doc "I return the modules within `app` that call `mod`."
  @spec callers(module(), atom()) :: [module()]
  def callers(mod, app) do
    for {from, ^mod} <- module_graph(app), do: from
  end

  @doc """
  I return aggregate stats across all loaded applications.

  Returns a map with `:apps`, `:modules`, `:functions`,
  `:with_docs`, and `:with_source` counts.
  """
  @spec system_stats() :: map()
  def system_stats do
    zero = %{modules: 0, functions: 0, with_docs: 0, with_source: 0}

    Application.loaded_applications()
    |> Enum.flat_map(fn {app, _, _} -> modules(app) end)
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
        modules(app)
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
    modules(app)
    |> Enum.map(fn mod ->
      %{module: inspect(mod), has_mod_doc: module_has_doc?(mod), functions: fun_docs(mod)}
    end)
    |> Enum.sort_by(& &1.module)
  end

  defp fun_docs(mod) do
    case Code.fetch_docs(mod) do
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
  I extract the top-level `defmodule X.Y` name from `source`. Returns
  the dotted module string, or nil when the source doesn't define one
  or doesn't parse.
  """

  @doc """
  I return every module `source` defines (nested `defmodule`s and
  `typedstruct module:` children included) as dotted-name strings.
  Returns `[]` when the source doesn't parse.
  """

  @doc """
  I parse `source` and return the AST function entries (the same shape
  `all_functions/1` returns minus the runtime-export merging, which
  needs the module to be loaded). Works on disk bytes alone, so safe
  to call before / after a failed compile.
  """

  @doc """
  I swap two functions (by `{name, arity}`) within `module` in `source`,
  taking ranges from `source` itself so the splice can't drift. Unknown
  name/arity returns `source` unchanged.
  """

  @doc """
  I replace the `{name, arity}` function within `module` in `source` with
  `new_text` (or remove it when `new_text` is empty), taking the range from
  `source` itself so the splice can't drift. Unknown name/arity returns
  `source` unchanged.
  """

  @doc """
  I append `new_text` as a new function just before `module`'s closing `end`,
  located from the parse so a sibling or nested module in the same file doesn't
  misdirect it. Returns `source` unchanged when `module` has no `defmodule` to
  append to (e.g. a typedstruct-generated module), or the source doesn't parse.
  """

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

    specs = beam_specs_by_arity(mod)

    runtime_extra =
      for {n, a} <- safe_exported_functions(mod),
          name_str = Atom.to_string(n),
          # Skip __struct__, __info__, __views__, etc. — internal/macro
          # plumbing the user doesn't want in their function list.
          not String.starts_with?(name_str, "__"),
          not MapSet.member?(ast_keys, {name_str, a}) do
        runtime_stub(name_str, a, Map.get(specs, {n, a}))
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
    modules(app)
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

    modules(app)
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

  @doc """
  I return all modules that define a function with the given name and
  optional arity. Includes `def`, `defp`, and macro-generated functions.
  """
  @spec implementors(atom(), non_neg_integer() | nil) :: [map()]
  def implementors(name, arity \\ nil) do
    name_str = Atom.to_string(name)

    Application.loaded_applications()
    |> Enum.flat_map(fn {app, _, _} -> modules(app) end)
    |> Enum.filter(fn mod ->
      Code.ensure_loaded?(mod) and function_exported?(mod, :__info__, 1)
    end)
    |> Enum.flat_map(fn mod -> module_implementors(mod, name_str, arity) end)
    |> Enum.sort_by(&{&1.module, &1.arity})
  end

  # I return all entries (with source if available, stubs otherwise)
  # for a function in a module. Merges AST extraction with runtime
  # exports so we catch defp (AST-only) and macro-generated functions
  # (exports-only).
  defp module_implementors(mod, name_str, arity) do
    name_atom = String.to_atom(name_str)
    mod_str = inspect(mod)
    funs = all_functions(mod)

    ast_entries =
      funs
      |> Enum.filter(&(&1.name == name_str and (arity == nil or &1.arity == arity)))
      |> Enum.map(&Map.put(&1, :module, mod_str))

    ast_arities = for e <- funs, e.name == name_str, into: MapSet.new(), do: e.arity

    exported_arities =
      for {n, a} <- safe_exported_functions(mod), n == name_atom, do: a

    specs = beam_specs_by_arity(mod)

    extra =
      for a <- exported_arities,
          arity == nil or a == arity,
          not MapSet.member?(ast_arities, a) do
        Map.put(runtime_stub(name_str, a, Map.get(specs, {name_atom, a})), :module, mod_str)
      end

    entries =
      (ast_entries ++ extra)
      |> Enum.map(fn e ->
        case e.start == 0 && covering_def(funs, name_str, e.arity) do
          %{} = c -> Map.put(c, :module, mod_str)
          _ -> e
        end
      end)
      |> Enum.uniq()

    # A private default-arg head is neither exported nor in the AST;
    # it still resolves to the def that generates it.
    case {entries, arity} do
      {[], a} when is_integer(a) ->
        covering_def(funs, name_str, a) |> List.wrap() |> Enum.map(&Map.put(&1, :module, mod_str))

      _ ->
        entries
    end
  end

  # `def foo(a, b \\ :x)` generates foo/1 with no def of its own;
  # resolve such an arity to the def that generates it.
  defp covering_def(funs, name_str, a) do
    funs
    |> Enum.filter(
      &(&1.name == name_str and &1.arity > a and &1.start > 0 and
          String.starts_with?(to_string(&1.kind), "def"))
    )
    |> Enum.sort_by(& &1.arity)
    |> Enum.find(&(a >= &1.arity - Map.get(&1, :defaults, 0)))
  end

  @doc """
  I return all call sites of `mod.name/arity` across loaded applications.

  Each result has `:module` (calling module), `:function` (calling function),
  and `:arity`.

  When `mod` is nil I match callers of `name/arity` regardless of
  target module — used by GT-side C-n when the call is a runtime
  variable (`builder.text(...)`, `&1.inserted_at`) or an unqualified
  Kernel/imported function and we can't statically know the target.
  """
  @spec function_references(module() | nil, atom(), non_neg_integer() | nil) :: [map()]
  def function_references(mod, name, arity \\ nil) do
    case GtBridge.Xref.q(~c"E") do
      {:ok, edges} ->
        callers =
          for {{from_mod, from_fn, from_ar}, {to_mod, to_fn, to_ar}} <- edges,
              mod == nil or to_mod == mod,
              to_fn == name,
              arity == nil or to_ar == arity,
              from_mod != mod,
              uniq: true do
            {from_mod, Atom.to_string(from_fn), from_ar}
          end

        callers
        |> Enum.uniq()
        |> Enum.flat_map(fn {from_mod, from_name, from_ar} ->
          all_functions(from_mod)
          |> Enum.filter(fn f -> f.name == from_name and f.arity == from_ar end)
          |> Enum.map(&Map.put(&1, :module, inspect(from_mod)))
        end)
        |> Enum.sort_by(&{&1.module, &1.name})

      _ ->
        []
    end
  end

  @doc """
  I parse Elixir source and return uniquely resolvable remote call sites.

  Each result has `:target_module`, `:function`, `:arity`, `:line`,
  and `:column`. Only fully qualified and alias-resolved remote calls
  are returned.
  """
  @spec call_sites(String.t(), module() | nil) :: [map()]
  def call_sites(source, context_module \\ nil) do
    # Smalltalk text uses CR (\r, 0x0D) as line separator while
    # Code.string_to_quoted only recognizes \n (and \r\n) — lone \r
    # leaves the whole source on a single line as far as the
    # tokenizer is concerned, so multi-line snippets returned []
    # call sites and the editor showed no |> triangles.  Normalize
    # all common variants to \n before hashing/parsing so
    # semantically-equivalent sources cache to the same key.
    source = source |> String.replace("\r\n", "\n") |> String.replace("\r", "\n")

    GtBridge.CacheReaper.cached(
      {:call_sites, context_module, :erlang.phash2(source)},
      fn -> compute_call_sites(source, context_module) end
    )
  end

  defp compute_call_sites(source, context_module) do
    with {:ok, ast} <- Source.quoted(source) do
      aliases =
        case context_module do
          nil ->
            GtBridge.Analysis.Walker.extract_alias_map(source)

          mod ->
            module_alias_map(mod)
            |> Map.merge(GtBridge.Analysis.Walker.extract_alias_map(source))
        end

      imports =
        case context_module do
          nil ->
            GtBridge.Analysis.Walker.extract_import_map(source)

          mod ->
            module_import_map(mod)
            |> Map.merge(GtBridge.Analysis.Walker.extract_import_map(source))
        end

      calls =
        ast
        |> GtBridge.Analysis.Walker.collect_calls(context_module)
        |> GtBridge.Analysis.Walker.resolve_call_aliases(aliases)
        |> GtBridge.Analysis.Walker.resolve_import_targets(imports)

      # A cross-module call can't reach a private fn, so exports are the
      # full callable set (no parse); the context adds its local defs from
      # the AST already parsed above.
      modules_in_calls = calls |> Enum.map(& &1.target_module) |> Enum.uniq()
      context_str = context_module && inspect(context_module)

      # Bare local calls resolve against the source's own defs (defp too)
      # whether or not a context module was given.  collect_calls/2 tags
      # them with the context name, or "" when none was passed, so the
      # local set is keyed under whichever it used.
      local_key = context_str || ""

      local_names =
        MapSet.union(
          Source.source_function_names(source, ast),
          if(context_module,
            do: MapSet.union(exported_names(context_str), module_local_names(context_module)),
            else: MapSet.new()
          )
        )

      defined =
        Map.new(modules_in_calls, fn mod_str ->
          names = if mod_str == local_key, do: local_names, else: exported_names(mod_str)
          {mod_str, names}
        end)

      Enum.filter(calls, fn site ->
        names = Map.get(defined, site.target_module, MapSet.new())
        MapSet.member?(names, site.function)
      end)
    else
      _ -> []
    end
  end

  @doc """
  I check whether each name in `names` (dotted Elixir module name
  strings, e.g. "GtBridge.Eval") is a currently-loaded module, and
  return a `%{name => boolean()}` map.

  Backed by the `Analysis.LoadedModules` ETS-backed set, which is
  populated initially from `:application.get_key/2` and maintained
  additively by EventBroker `%ModuleEvent{}` events — so each
  lookup is O(1) and stays fresh without recompute.

  Used by GT-side `BeamModuleResolution`: the styler walks source
  locally with the SmaCC `ElixirParser`, finds module-name
  candidates, batches the unknowns, and asks me once per source
  change for their resolution status.  After warm-up the GT cache
  holds answers for every name in the user's workspace and bridge
  calls go to zero.
  """
  @spec modules_loaded?([String.t()]) :: %{String.t() => boolean()}
  def modules_loaded?(names) when is_list(names) do
    Map.new(names, fn name ->
      {to_string(name), GtBridge.Analysis.LoadedModules.loaded?(to_string(name))}
    end)
  end

  # A module's exported functions, macros, and public types — the names
  # a cross-module call or type reference can reach.
  defp exported_names(nil), do: MapSet.new()

  defp exported_names(mod_str) do
    mod = Module.concat([mod_str])

    if Code.ensure_loaded?(mod) and GtBridge.Resolve.source_file(mod) != nil do
      (safe_module_info(mod, :functions) ++ safe_module_info(mod, :macros))
      |> Enum.map(fn {name, _arity} -> Atom.to_string(name) end)
      |> Enum.concat(exported_type_names(mod))
      |> MapSet.new()
    else
      MapSet.new()
    end
  end

  # Type names come from the beam chunk, not __info__; cache by md5 so
  # referenced modules stay warm across edits.
  defp exported_type_names(mod) do
    cached_by_md5(:exported_types, mod, fn ->
      case Code.Typespec.fetch_types(mod) do
        {:ok, types} ->
          for {kind, {name, _, _}} <- types, kind in [:type, :opaque], do: Atom.to_string(name)

        _ ->
          []
      end
    end)
  rescue
    _ -> []
  end

  @doc "I resolve an alias name using a context module's alias declarations."
  @spec resolve_alias(module(), String.t()) :: String.t()
  def resolve_alias(context_module, alias_name) do
    aliases = module_alias_map(context_module)
    Map.get(aliases, alias_name, alias_name)
  end

  @doc """
  I am true when `mod` defines a function (or macro-generated export)
  named `name`.  Used by GT-side C-n to decide whether an unqualified
  reference should be searched in `mod` (true) or fall back to
  cross-module implementors search (false).
  """
  @spec function_in_module?(module(), String.t() | atom()) :: boolean()
  def function_in_module?(mod, name) when is_atom(name),
    do: function_in_module?(mod, Atom.to_string(name))

  def function_in_module?(mod, name) when is_binary(name) do
    all_functions(mod) |> Enum.any?(&(&1.name == name))
  end

  # Parsing the saved source for aliases/imports is ~3ms each; cache by
  # md5, same as the type names.
  defp module_alias_map(mod) do
    cached_by_md5(:module_alias_map, mod, fn ->
      GtBridge.Resolve.with_source(mod, %{}, &GtBridge.Analysis.Walker.extract_alias_map/1)
    end)
  end

  defp module_import_map(mod) do
    cached_by_md5(:module_import_map, mod, fn ->
      GtBridge.Resolve.with_source(mod, %{}, &GtBridge.Analysis.Walker.extract_import_map/1)
    end)
  end

  # source_function_names on the module's saved source (the same
  # extraction the source view runs on the live buffer), so a
  # single-function view resolves calls to the module's own defs.
  defp module_local_names(mod) do
    cached_by_md5(:module_local_names, mod, fn ->
      GtBridge.Resolve.with_source(mod, MapSet.new(), fn src ->
        case Source.quoted(src) do
          {:ok, ast} -> Source.source_function_names(src, ast)
          _ -> MapSet.new()
        end
      end)
    end)
  end

  @doc """
  I return `mod`'s `alias` declarations as a list of
  `[short_name, full_name]` pairs.

  GT-side wrench detection in inline function editors (the |>
  expander, the Meta browser's Functions tab) shows only a function
  body — the surrounding `alias` lines aren't visible in source, so
  bare references like `ColumnedList` look unresolved even when the
  enclosing module aliases them.  The styler calls me to merge the
  module's aliases into its local map before classifying.

  I return a list (rather than a map) so the Smalltalk side can
  iterate via `asList` without needing `attributeAt:` per name —
  Maps come back as opaque proxies on the GT side.
  """
  @spec module_aliases(module()) :: [[String.t()]]
  def module_aliases(mod) do
    module_alias_map(mod) |> Enum.map(fn {short, full} -> [short, full] end)
  end

  @doc "I return exported functions for a module (works for both Elixir and Erlang)."
  @spec exported_functions(module()) :: [map()]
  def exported_functions(mod) do
    funs =
      if function_exported?(mod, :__info__, 1) do
        safe_exported_functions(mod)
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

  defp safe_exported_functions(mod), do: safe_module_info(mod, :functions)

  # __info__/1 can raise for some macro-only modules despite exporting it,
  # so the try/rescue is mandatory.
  defp safe_module_info(mod, kind) do
    if function_exported?(mod, :__info__, 1) do
      try do
        mod.__info__(kind)
      rescue
        _ in [UndefinedFunctionError, ArgumentError] -> []
      end
    else
      []
    end
  end

  # I return %{{name, arity} => formatted_spec_string} for every
  # function in the module that the BEAM has a typespec for.  Used
  # to enrich macro-generated function entries (which have no source)
  # with a synthesized @spec line so the user sees the type info
  # even though there's no AST.
  defp beam_specs_by_arity(mod) do
    case Code.Typespec.fetch_specs(mod) do
      {:ok, specs} ->
        Map.new(specs, fn {{name, arity}, [spec | _]} ->
          formatted = Code.Typespec.spec_to_quoted(name, spec) |> Macro.to_string()
          {{name, arity}, formatted}
        end)

      _ ->
        %{}
    end
  end

  # I build the placeholder source for a function with no AST entry.
  # When the BEAM has a typespec for it I prepend an @spec line so the
  # type info shows up in the editor; otherwise just the comment.
  # The shape of an exports-only entry: a runtime function with no
  # textual def, carrying a synthesized source.
  defp runtime_stub(name_str, arity, spec) do
    %{
      name: name_str,
      arity: arity,
      kind: :def,
      start: 0,
      end_line: 0,
      sig: "#{name_str}/#{arity}",
      source: synth_no_source(name_str, arity, spec)
    }
  end

  defp synth_no_source(name_str, arity, nil),
    do: "# #{name_str}/#{arity}, no source"

  defp synth_no_source(name_str, arity, spec_string),
    do: "@spec #{spec_string}\n# #{name_str}/#{arity}, no source"

  # I read the LoadedModules projection, not :application.get_key, so
  # modules created by a live recompile (a new file, or a nested module
  # from typedstruct module:) are enumerated instead of being frozen at
  # the boot-time app spec.
  # Read-through cache keyed by the module's md5: the key
  # self-invalidates on recompile and CacheReaper sweeps leftovers.
  defp cached_by_md5(tag, mod, fun) do
    GtBridge.CacheReaper.cached({tag, mod, safe_module_info(mod, :md5)}, fun)
  end

  defp modules(app) do
    GtBridge.Analysis.LoadedModules.modules_for_app(app)
  end

  defp module_doc_info(mod) do
    try do
      case Code.fetch_docs(mod) do
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
