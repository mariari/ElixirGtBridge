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

  @doc "I return the modules that `mod` calls."
  @spec callees(module()) :: [module()]
  def callees(mod) do
    case Application.get_application(mod) do
      nil -> []
      app -> callees(mod, app)
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
  I return all function definitions with complete line ranges.

  Each entry includes `:start` (extended back to include @doc/@spec),
  `:end_line`, `:name`, `:arity`, `:kind`, `:sig`, and `:source`
  (the source text for that function including annotations).

  AST entries are merged with runtime exports from `__info__(:functions)`
  so macro-generated functions (e.g. `defview`, `defstruct` field
  accessors, etc.) are visible. Runtime-only entries get default
  `start: 0`, `end_line: 0`, `kind: :def`, and a placeholder source.
  """
  @spec all_functions(module()) :: [map()]
  def all_functions(mod) do
    ast_entries =
      GtBridge.Resolve.with_source(mod, [], fn source ->
        case Code.string_to_quoted(source, columns: true, token_metadata: true) do
          {:ok, ast} ->
            lines = String.split(source, "\n")

            extract_functions(ast)
            |> merge_clauses()
            |> Enum.map(fn f ->
              start = walk_back_annotations(lines, f.start)
              source_text = Enum.slice(lines, (start - 1)..(f.end_line - 1)) |> Enum.join("\n")
              %{f | start: start} |> Map.put(:source, source_text)
            end)

          _ ->
            []
        end
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
        %{
          name: name_str,
          arity: a,
          kind: :def,
          start: 0,
          end_line: 0,
          sig: "#{name_str}/#{a}",
          source: synth_no_source(name_str, a, Map.get(specs, {n, a}))
        }
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

    type_extras = type_entries(mod)

    {placed_types, orphan_types} = Enum.split_with(type_extras, &(&1.start > 0))

    {grouped, _} =
      (ast_entries ++ placed_types)
      |> Enum.sort_by(& &1.start)
      |> Enum.flat_map_reduce(MapSet.new(), fn entry, seen ->
        if MapSet.member?(seen, entry.name) do
          {[entry], seen}
        else
          sibs = siblings_by_name |> Map.get(entry.name, []) |> Enum.sort_by(& &1.arity)
          {sibs ++ [entry], MapSet.put(seen, entry.name)}
        end
      end)

    grouped ++ orphans ++ orphan_types
  end

  # I return entries for every @type / @opaque / @typep on `mod`, in the
  # same shape as function entries.  The `t/0` row of a typedstruct module
  # gets the typedstruct block as source (and that block's start line) so
  # the row sorts in source order with the rest of the module's
  # definitions; @type / @opaque / @typep declarations get their own
  # source line.  Types we can't locate in source fall back to start = 0
  # and a rendered `@type name() :: body` line.
  defp type_entries(mod) do
    case Code.Typespec.fetch_types(mod) do
      {:ok, types} ->
        info = type_source_info(mod)

        Enum.map(types, fn {kind, {name, _, args}} = entry ->
          arity = length(args)
          name_str = Atom.to_string(name)

          {start, end_line, source} =
            case Map.get(info, name) do
              {s, e, src} -> {s, e, src}
              nil -> {0, 0, render_type_body(entry)}
            end

          %{
            name: name_str,
            arity: arity,
            kind: kind,
            start: start,
            end_line: end_line,
            sig: "#{name_str}/#{arity}",
            source: source
          }
        end)

      _ ->
        []
    end
  end

  defp render_type_body({_kind, type_data}) do
    "@type " <> (Code.Typespec.type_to_quoted(type_data) |> Macro.to_string())
  end

  # I return %{type_name_atom => {start, end_line, source}} for everything
  # we can locate in `mod`'s source — typedstruct blocks (mapped to the
  # `t` type) and @type / @opaque / @typep declarations.  typedstruct wins
  # on collision since the block is more useful than its synthesized
  # `@type t :: %Mod{...}`.
  defp type_source_info(mod) do
    GtBridge.Resolve.with_source(mod, %{}, fn source ->
      case Code.string_to_quoted(source, columns: true, token_metadata: true) do
        {:ok, ast} ->
          lines = String.split(source, "\n")
          decl_info = find_type_decl_locations(ast, lines)

          ts_info =
            case find_typedstruct_lines(ast) do
              {s, e} -> %{t: {s, e, slice_lines(lines, s, e)}}
              _ -> %{}
            end

          Map.merge(decl_info, ts_info)

        _ ->
          %{}
      end
    end)
  end

  defp find_typedstruct_lines(ast) do
    {_, found} =
      Macro.prewalk(ast, nil, fn
        {:typedstruct, meta, [[do: _]]} = node, nil ->
          s = Keyword.get(meta, :line)
          e = get_in(meta, [:end, :line]) || s
          {node, {s, e}}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp find_type_decl_locations(ast, lines) do
    {_, found} =
      Macro.prewalk(ast, %{}, fn
        {:@, meta,
         [
           {kind, _, [{:"::", _, [{name, _, _args} | _]}]}
         ]} = node,
        acc
        when kind in [:type, :opaque, :typep] and is_atom(name) ->
          s = Keyword.get(meta, :line)
          e = get_in(meta, [:end_of_expression, :line]) || s
          {node, Map.put(acc, name, {s, e, slice_lines(lines, s, e)})}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp slice_lines(lines, s, e),
    do: Enum.slice(lines, (s - 1)..(e - 1)) |> Enum.join("\n")

  defp merge_clauses(entries) do
    # Merge consecutive entries with the same name/arity/kind
    # into a single entry spanning all clauses.
    Enum.reduce(Enum.reverse(entries), [], fn entry, acc ->
      case acc do
        [prev | rest]
        when prev.name == entry.name and prev.arity == entry.arity and prev.kind == entry.kind ->
          [%{entry | end_line: prev.end_line} | rest]

        _ ->
          [entry | acc]
      end
    end)
  end

  defp walk_back_annotations(lines, def_start) do
    if def_start <= 1 do
      def_start
    else
      Enum.reduce_while((def_start - 1)..1//-1, {def_start, false}, fn i, {acc, in_heredoc} ->
        trimmed = String.trim(Enum.at(lines, i - 1, ""))

        cond do
          String.starts_with?(trimmed, "defmodule") -> {:halt, {acc, false}}
          String.starts_with?(trimmed, "@doc") -> {:halt, {i, false}}
          String.starts_with?(trimmed, "@spec") -> {:cont, {i, false}}
          String.starts_with?(trimmed, "@impl") -> {:cont, {i, false}}
          String.starts_with?(trimmed, "#") -> {:cont, {i, in_heredoc}}
          trimmed == ~s(""") -> {:cont, {i, true}}
          in_heredoc -> {:cont, {i, true}}
          trimmed == "" -> {:halt, {acc, false}}
          acc < def_start -> {:cont, {i, in_heredoc}}
          true -> {:halt, {acc, false}}
        end
      end)
      |> elem(0)
    end
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

  @doc "I return all module names across all loaded applications, sorted."
  @spec all_module_names() :: [String.t()]
  def all_module_names do
    Application.loaded_applications()
    |> Enum.flat_map(fn {app, _, _} -> modules(app) end)
    |> Enum.map(&inspect/1)
    |> Enum.sort()
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

    ast_entries =
      all_functions(mod)
      |> Enum.filter(&(&1.name == name_str and (arity == nil or &1.arity == arity)))
      |> Enum.map(&Map.put(&1, :module, mod_str))

    ast_arities = ast_entries |> Enum.map(& &1.arity) |> MapSet.new()

    exported_arities =
      for {n, a} <- safe_exported_functions(mod), n == name_atom, do: a

    specs = beam_specs_by_arity(mod)

    extra =
      for a <- exported_arities,
          arity == nil or a == arity,
          not MapSet.member?(ast_arities, a) do
        %{
          module: mod_str,
          name: name_str,
          arity: a,
          kind: :def,
          start: 0,
          end_line: 0,
          sig: "#{name_str}/#{a}",
          source: synth_no_source(name_str, a, Map.get(specs, {name_atom, a}))
        }
      end

    ast_entries ++ extra
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
    with {:ok, ast} <- Code.string_to_quoted(source, columns: true, token_metadata: true) do
      aliases =
        case context_module do
          nil ->
            GtBridge.Analysis.Walker.extract_alias_map(source)

          mod ->
            module_alias_map(mod)
            |> Map.merge(GtBridge.Analysis.Walker.extract_alias_map(source))
        end

      calls =
        ast
        |> GtBridge.Analysis.Walker.collect_calls(context_module)
        |> GtBridge.Analysis.Walker.resolve_call_aliases(aliases)

      # Build a per-module lookup of defined function names for filtering.
      # Includes both def and defp via all_functions/1 (AST-based).
      modules_in_calls = calls |> Enum.map(& &1.target_module) |> Enum.uniq()

      defined =
        Map.new(modules_in_calls, fn mod_str ->
          {mod_str, defined_function_names(mod_str)}
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

  defp defined_function_names(mod_str) do
    mod = Module.concat([mod_str])

    if Code.ensure_loaded?(mod) and GtBridge.Resolve.source_file(mod) != nil do
      ast_names = all_functions(mod) |> Enum.map(& &1.name) |> MapSet.new()

      exported_names =
        safe_exported_functions(mod)
        |> Enum.map(fn {n, _} -> Atom.to_string(n) end)
        |> MapSet.new()

      MapSet.union(ast_names, exported_names)
    else
      MapSet.new()
    end
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

  @doc """
  I return the source for a function or type in `mod` matching
  `name`/`arity`.  Used by the inline `|>` expander, which attaches
  both to function calls and to type references in @spec / typedstruct
  field types.  Returns nil when no entry matches.
  """
  @spec function_or_type_source(module(), String.t(), non_neg_integer()) :: String.t() | nil
  def function_or_type_source(mod, name, arity) do
    case Enum.find(all_functions(mod), &(&1.name == name and &1.arity == arity)) do
      %{source: src} -> src
      nil -> nil
    end
  end

  defp module_alias_map(mod) do
    GtBridge.Resolve.with_source(mod, %{}, &GtBridge.Analysis.Walker.extract_alias_map/1)
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

  # I return [{name_atom, arity}] from mod.__info__(:functions),
  # or [] if the module doesn't export __info__/1 or raises.
  # Several call sites need this: macro-only modules sometimes
  # raise inside __info__(:functions) despite exporting it, so
  # the try/rescue is mandatory wherever we call it.
  defp safe_exported_functions(mod) do
    if function_exported?(mod, :__info__, 1) do
      try do
        mod.__info__(:functions)
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
  defp synth_no_source(name_str, arity, nil),
    do: "# #{name_str}/#{arity}, no source"

  defp synth_no_source(name_str, arity, spec_string),
    do: "@spec #{spec_string}\n# #{name_str}/#{arity}, no source"


  defp modules(app) do
    case :application.get_key(app, :modules) do
      {:ok, mods} -> mods
      _ -> []
    end
  end

  defp extract_functions({:defmodule, _, [_, [do: {:__block__, _, body}]]}) do
    Enum.flat_map(body, &function_entry/1)
  end

  defp extract_functions(_), do: []

  # Atoms that look like function definers (def, defp, defmacro, defmacrop,
  # plus user macros like defview) but aren't function-defining themselves.
  @non_function_def_kinds [
    :defmodule,
    :defstruct,
    :defguard,
    :defguardp,
    :defprotocol,
    :defimpl,
    :defdelegate,
    :deftype,
    :defrecord,
    :defrecordp,
    :defexception,
    :defoverridable
  ]

  # User-level macros that expand to function definitions and
  # whose AST source we want captured so the inspector shows the
  # body. Without this allowlist they fall through to the runtime
  # export path and render as "(no source)".
  @function_def_macros [:example]

  defp function_entry({kind, meta, [head | _]}) when is_atom(kind) do
    kind_str = Atom.to_string(kind)

    cond do
      kind in @function_def_macros ->
        function_entry_for("def", head, meta)

      not String.starts_with?(kind_str, "def") ->
        []

      kind in @non_function_def_kinds ->
        []

      true ->
        function_entry_for(kind_str, head, meta)
    end
  end

  defp function_entry(_), do: []

  defp function_entry_for(kind_str, head, meta) do
    case function_head(head) do
      {name, arity} when is_atom(name) and is_integer(arity) ->
        function_record(kind_str, name, arity, meta)

      _ ->
        []
    end
  end

  defp function_record(kind_str, name, arity, meta) do
    end_line = meta[:end][:line] || meta[:end_of_expression][:line] || meta[:line]

    [
      %{
        name: Atom.to_string(name),
        arity: arity,
        kind: kind_str,
        start: meta[:line],
        end_line: end_line,
        sig: "#{name}/#{arity}"
      }
    ]
  end

  defp function_head({:when, _, [head | _]}), do: function_head(head)
  defp function_head({name, _, args}) when is_atom(name) and is_list(args),
    do: {name, length(args)}
  defp function_head({name, _, _}) when is_atom(name), do: {name, 0}
  defp function_head(name) when is_atom(name), do: {name, 0}
  # Catch-all so non-name heads (e.g. `__aliases__` tuples wrapped
  # by some macro form) fall through to the case clause's `[]`
  # branch instead of raising FunctionClauseError.
  defp function_head(_), do: nil

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
