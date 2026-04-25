# credo:disable-for-this-file
defmodule GtBridge.Analysis do
  # mnesia is an optional runtime dependency — not available at compile time
  @compile {:no_warn_undefined, [:mnesia]}
  @moduledoc """
  I provide static analysis data for GT visualization.

  I use `:xref` to extract module-level call graphs from compiled
  BEAM files and `Code.fetch_docs/1` for documentation coverage.
  I return raw data — GT builds the views.

  ### Public API

  - `module_graph/1` — module→module call edges for an application
  - `callees/1` — modules called by a given module
  - `callers/2` — modules that call a given module within an app
  """

  @type edge :: {module(), module()}
  @infrastructure_apps MapSet.new([:kernel, :stdlib, :elixir, :compiler, :logger])

  @doc """
  I return module-level call edges for an application.

  Each edge `{from, to}` means `from` contains a call to a function
  in `to`. Self-edges are excluded. Only modules whose BEAM files
  are on the code path are analyzed.
  """
  @spec module_graph(atom()) :: [edge()]
  def module_graph(app) do
    with_xref(app, fn server ->
      {:ok, pairs} = :xref.q(server, ~c"E ||| V")

      for {{from, _, _}, {to, _, _}} <- pairs, from != to, uniq: true, do: {from, to}
    end)
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
      with path when is_binary(path) <- GtBridge.Resolve.source_file(mod),
           {:ok, source} <- File.read(path),
           {:ok, ast} <- Code.string_to_quoted(source, columns: true, token_metadata: true) do
        lines = String.split(source, "\n")

        extract_functions(ast)
        |> merge_clauses()
        |> Enum.map(fn f ->
          start = walk_back_annotations(lines, f.start)
          source_text = Enum.slice(lines, (start - 1)..(f.end_line - 1)) |> Enum.join("\n")
          %{f | start: start} |> Map.put(:source, source_text)
        end)
      else
        _ -> []
      end

    ast_keys = ast_entries |> Enum.map(&{&1.name, &1.arity}) |> MapSet.new()

    runtime_extra =
      try do
        for {n, a} <- mod.__info__(:functions),
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
            source: "# macro-generated, no source"
          }
        end
      rescue
        _ -> []
      end

    # Sort by source line. Runtime-only entries (start: 0) go to the end
    # so source-order is preserved for AST entries.
    (ast_entries ++ runtime_extra)
    |> Enum.sort_by(fn f -> {f.start == 0, f.start} end)
  end

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

  @doc """
  I create or return an eval session with a module's preamble loaded.

  Walks the source file's use/import/alias/require lines and evals
  them into the session's env, so completion works in context.
  Returns the session ID.
  """
  @spec editor_session(module(), String.t()) :: String.t()
  def editor_session(mod, sid) do
    # Create the session if it doesn't exist — safe for module
    # coder sessions which use synchronous eval (no port needed)
    pid = GtBridge.EvalRegistry.get_or_create(sid)
    load_imports(mod, pid)
    sid
  end

  defp load_imports(mod, pid) do
    state = :sys.get_state(pid)

    base_env = eval_into_env("import #{inspect(mod)}", state.env)

    new_env =
      with path when is_binary(path) <- GtBridge.Resolve.source_file(mod),
           {:ok, source} <- File.read(path) do
        source
        |> preamble_directives()
        |> Enum.reduce(base_env, &eval_into_env/2)
      else
        _ -> base_env
      end

    :sys.replace_state(pid, fn s -> %{s | env: new_env} end)
  end

  # Skip "use " — it requires a module context and crashes in
  # eval env (e.g. "use TypedStruct" triggers __meta__ errors)
  @preamble_starts ["import ", "alias ", "require "]

  @doc "I return the alias/import/require lines from a module's source."
  @spec preamble_directives(module()) :: [String.t()]
  def preamble_directives(mod) when is_atom(mod) do
    with path when is_binary(path) <- GtBridge.Resolve.source_file(mod),
         {:ok, source} <- File.read(path) do
      preamble_directives(source)
    else
      _ -> []
    end
  end

  def preamble_directives(source) when is_binary(source) do
    source
    |> String.split("\n")
    |> Stream.map(&String.trim/1)
    |> Stream.take_while(fn line ->
      not (String.starts_with?(line, "def ") or String.starts_with?(line, "defp "))
    end)
    |> Enum.filter(fn line ->
      Enum.any?(@preamble_starts, &String.starts_with?(line, &1))
    end)
  end

  defp eval_into_env(line, env) do
    # Suppress compiler diagnostics (e.g. Ecto's __meta__ warnings)
    # during preamble eval — they're harmless but noisy in the terminal
    old = Code.get_compiler_option(:no_warn_undefined)
    Code.put_compiler_option(:no_warn_undefined, :all)

    try do
      {_, _, new_env} = Code.eval_quoted_with_env(Code.string_to_quoted!(line), [], env)
      new_env
    rescue
      _ -> env
    after
      Code.put_compiler_option(:no_warn_undefined, old)
    end
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

    # Defensive: even though the caller filters for function_exported?
    # __info__/1, some modules raise inside __info__(:functions) (e.g.
    # macro-only modules with no compiled function table).
    exported_arities =
      try do
        for {n, a} <- mod.__info__(:functions), n == name_atom, do: a
      rescue
        _ -> []
      end

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
          source: "# macro-generated, no source"
        }
      end

    ast_entries ++ extra
  end

  @doc """
  I return all call sites of `mod.name/arity` across loaded applications.

  Each result has `:module` (calling module), `:function` (calling function),
  and `:arity`.
  """
  @spec function_references(module(), atom(), non_neg_integer() | nil) :: [map()]
  def function_references(mod, name, arity \\ nil) do
    target_app = Application.get_application(mod)

    apps_to_scan(target_app)
    |> Enum.flat_map(fn app ->
      with_xref(app, fn server ->
        case :xref.q(server, ~c"E") do
          {:ok, edges} ->
            for {{from_mod, from_fn, from_ar}, {to_mod, to_fn, to_ar}} <- edges,
                to_mod == mod,
                to_fn == name,
                arity == nil or to_ar == arity,
                from_mod != mod,
                uniq: true do
              {from_mod, Atom.to_string(from_fn), from_ar}
            end

          _ ->
            []
        end
      end)
    end)
    |> Enum.uniq()
    |> Enum.flat_map(fn {from_mod, from_name, from_ar} ->
      all_functions(from_mod)
      |> Enum.filter(fn f -> f.name == from_name and f.arity == from_ar end)
      |> Enum.map(&Map.put(&1, :module, inspect(from_mod)))
    end)
    |> Enum.sort_by(&{&1.module, &1.name})
  end

  # I return apps worth scanning for references.
  # For infrastructure targets (Enum, Kernel, etc.) only scan the
  # main project — scanning all deps would be slow and noisy.
  # For project/dep targets, scan the target app, main project,
  # and direct dependents.
  defp apps_to_scan(target_app) do
    main = Mix.Project.config()[:app]

    if MapSet.member?(@infrastructure_apps, target_app) do
      [main] |> Enum.reject(&is_nil/1)
    else
      dependents =
        for {app, _, _} <- Application.loaded_applications(),
            not MapSet.member?(@infrastructure_apps, app),
            dep <- Application.spec(app, :applications) || [],
            dep == target_app,
            do: app

      ([target_app, main | dependents] -- [nil])
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(@infrastructure_apps, &1))
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
    with {:ok, ast} <- Code.string_to_quoted(source, columns: true, token_metadata: true) do
      aliases =
        case context_module do
          nil -> extract_alias_map(source)
          mod -> module_alias_map(mod) |> Map.merge(extract_alias_map(source))
        end

      calls = ast |> collect_remote_calls(context_module) |> resolve_call_aliases(aliases)

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

  defp defined_function_names(mod_str) do
    mod = Module.concat([mod_str])

    if Code.ensure_loaded?(mod) and function_exported?(mod, :__info__, 1) and
         GtBridge.Resolve.source_file(mod) != nil do
      ast_names = all_functions(mod) |> Enum.map(& &1.name) |> MapSet.new()

      # Defensive: see module_implementors — some modules raise inside
      # __info__(:functions) despite exporting __info__/1.
      exported_names =
        try do
          mod.__info__(:functions)
          |> Enum.map(fn {n, _} -> Atom.to_string(n) end)
          |> MapSet.new()
        rescue
          _ -> MapSet.new()
        end

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

  defp module_alias_map(mod) do
    case GtBridge.Resolve.source_file(mod) do
      nil -> %{}
      path -> path |> File.read!() |> extract_alias_map()
    end
  end

  @doc "I return root applications — apps not depended on by any other loaded app."
  @spec root_apps() :: [atom()]
  def root_apps do
    skip = @infrastructure_apps

    loaded =
      for {a, _, _} <- Application.loaded_applications(),
          a not in skip,
          into: MapSet.new(),
          do: a

    depended_on =
      for {a, _, _} <- Application.loaded_applications(),
          a not in skip,
          dep <- Application.spec(a, :applications) || [],
          dep not in skip,
          into: MapSet.new(),
          do: dep

    loaded
    |> MapSet.difference(depended_on)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  # I return {app, dep} pairs for every loaded application's
  # filtered deps. No self-edges.
  defp app_dep_edges do
    skip = @infrastructure_apps

    for {a, _, _} <- Application.loaded_applications(),
        a not in skip,
        dep <- Application.spec(a, :applications) || [],
        dep not in skip,
        do: {a, dep}
  end

  @doc "I return exported functions for a module (works for both Elixir and Erlang)."
  @spec exported_functions(module()) :: [map()]
  def exported_functions(mod) do
    funs =
      if function_exported?(mod, :__info__, 1) do
        mod.__info__(:functions)
      else
        mod.module_info(:exports)
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

  @doc "I return mnesia table info for the table list.
  Returns an empty list when mnesia is not started."
  @spec mnesia_tables() :: [map()]
  def mnesia_tables do
    if Code.ensure_loaded?(:mnesia) and :mnesia.system_info(:is_running) == :yes do
      :mnesia.system_info(:tables)
      |> Enum.reject(&(&1 == :schema))
      |> Enum.map(fn t ->
        %{
          name: Atom.to_string(t),
          size: :mnesia.table_info(t, :size),
          type: Atom.to_string(:mnesia.table_info(t, :type)),
          attrs: Enum.map_join(:mnesia.table_info(t, :attributes), ", ", &Atom.to_string/1)
        }
      end)
      |> Enum.sort_by(& &1.name)
    else
      []
    end
  end

  @doc "I return schema info for a mnesia table.
  Returns an empty map when mnesia is not running."
  @spec mnesia_schema(atom()) :: map()
  def mnesia_schema(table) do
    if Code.ensure_loaded?(:mnesia) and :mnesia.system_info(:is_running) == :yes do
      %{
        type: :mnesia.table_info(table, :type),
        size: :mnesia.table_info(table, :size),
        memory: :mnesia.table_info(table, :memory),
        storage: :mnesia.table_info(table, :storage_type),
        record_name: :mnesia.table_info(table, :record_name),
        attributes:
          Enum.map_join(:mnesia.table_info(table, :attributes), ", ", &Atom.to_string/1),
        indexes: inspect(:mnesia.table_info(table, :index)),
        access_mode: :mnesia.table_info(table, :access_mode),
        load_order: :mnesia.table_info(table, :load_order)
      }
    else
      %{}
    end
  end

  @doc "I return records from a mnesia table."
  @spec mnesia_records(atom(), non_neg_integer()) :: [list()]
  def mnesia_records(table, limit \\ 500) do
    attrs = :mnesia.table_info(table, :attributes)

    :mnesia.dirty_all_keys(table)
    |> Enum.take(limit)
    |> Enum.flat_map(fn key ->
      :mnesia.dirty_read(table, key)
      |> Enum.map(fn rec ->
        values = rec |> Tuple.to_list() |> tl()

        Enum.zip(attrs, values)
        |> Enum.map(fn {a, v} -> {Atom.to_string(a), inspect(v)} end)
      end)
    end)
  end

  @doc """
  I return a nested supervision tree starting from a PID.

  Each node is a map with `:pid`, `:name`, `:module`, `:supervisor`,
  `:children`, `:queue`, and `:status`. Large worker pools appear
  as-is — GT collapses them during rendering.
  """
  @spec supervision_tree(pid()) :: map()
  def supervision_tree(pid) when is_pid(pid), do: build_sup_node(pid)

  @doc """
  I return a reverse dependency tree — who depends on this app.

  Each node has `:name` and `:children` (apps that depend on it).
  """
  @spec app_reverse_dep_tree(atom()) :: map()
  def app_reverse_dep_tree(app) do
    reverse =
      app_dep_edges()
      |> Enum.reject(fn {a, b} -> a == b end)
      |> Enum.group_by(fn {_, dep} -> dep end, fn {a, _} -> a end)

    build_tree(app, fn a -> Map.get(reverse, a, []) |> Enum.sort() end, prune?: false)
  end

  @doc """
  I return a dependency tree rooted at an application.

  Each node has `:name` and `:children`. Transitive deps already
  reachable through a child are pruned. Cycles are broken by
  not revisiting already-seen apps.
  """
  @spec app_dep_tree(atom()) :: map()
  def app_dep_tree(app) do
    skip = @infrastructure_apps

    deps_fn = fn a ->
      (Application.spec(a, :applications) || [])
      |> Enum.reject(&MapSet.member?(skip, &1))
    end

    build_tree(app, deps_fn, prune?: true)
  end

  # I build a dependency tree node for `app` using `deps_fn` to find
  # children. With prune?: true, transitive children reachable through
  # another child are removed (so the tree shows minimal direct deps).
  defp build_tree(app, deps_fn, opts) do
    build_tree(app, deps_fn, MapSet.new(), Keyword.fetch!(opts, :prune?))
  end

  defp build_tree(app, deps_fn, visited, prune?) do
    if app in visited do
      %{name: Atom.to_string(app), children: []}
    else
      visited = MapSet.put(visited, app)
      children = Enum.map(deps_fn.(app), &build_tree(&1, deps_fn, visited, prune?))

      children =
        if prune? do
          grandchild_names = children |> Enum.flat_map(&all_dep_names/1) |> MapSet.new()
          Enum.reject(children, &MapSet.member?(grandchild_names, &1.name))
        else
          children
        end

      %{name: Atom.to_string(app), children: children}
    end
  end

  defp all_dep_names(%{children: children}) do
    Enum.flat_map(children, fn c -> [c.name | all_dep_names(c)] end)
  end

  ############################################################
  #                  Call Site Extraction                     #
  ############################################################

  defp extract_alias_map(source) do
    source
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      trimmed = String.trim(line)

      cond do
        match = Regex.run(~r/^alias\s+(\S+),\s*as:\s*(\w+)/, trimmed) ->
          [{Enum.at(match, 2), Enum.at(match, 1)}]

        match = Regex.run(~r/^alias\s+([\w.]+)$/, trimmed) ->
          full = Enum.at(match, 1)
          short = full |> String.split(".") |> List.last()
          [{short, full}]

        true ->
          []
      end
    end)
    |> Map.new()
  end

  defp collect_remote_calls(ast, context_module) do
    ctx_str = if context_module, do: inspect(context_module)
    walk_calls(ast, [], ctx_str)
  end

  # `a |> M.f(b)` parses as {:|>, _, [a, M.f(b)]} but means M.f(a, b),
  # so the right-hand call gets arity length(args) + 1. Walk the left
  # side normally and the right side as a pipe target.
  defp walk_calls({:|>, _, [left, right]}, acc, ctx) do
    walk_pipe_target(right, walk_calls(left, acc, ctx), ctx)
  end

  defp walk_calls(
         {{:., _, [{:__aliases__, _, parts}, fun]}, meta, args},
         acc,
         ctx
       )
       when is_atom(fun) and is_list(args) do
    acc = [remote_entry(parts, fun, length(args), meta) | acc]
    Enum.reduce(args, acc, fn n, a -> walk_calls(n, a, ctx) end)
  end

  # Local call: `foo(args)` where the function is defined in the current
  # module.  Only emitted when ctx is a string (i.e. we have a context
  # module).  Bogus matches (operators, special forms, kernel macros) are
  # filtered out by call_sites/2's defined_function_names check.
  defp walk_calls({fun, meta, args}, acc, ctx)
       when is_atom(fun) and is_list(args) and is_binary(ctx) do
    acc = [local_entry(ctx, fun, length(args), meta) | acc]
    Enum.reduce(args, acc, fn n, a -> walk_calls(n, a, ctx) end)
  end

  defp walk_calls({_, _, args}, acc, ctx) when is_list(args),
    do: Enum.reduce(args, acc, fn n, a -> walk_calls(n, a, ctx) end)

  defp walk_calls({a, b}, acc, ctx), do: walk_calls(b, walk_calls(a, acc, ctx), ctx)

  defp walk_calls(items, acc, ctx) when is_list(items),
    do: Enum.reduce(items, acc, fn n, a -> walk_calls(n, a, ctx) end)

  defp walk_calls(_, acc, _), do: acc

  defp walk_pipe_target(
         {{:., _, [{:__aliases__, _, parts}, fun]}, meta, args},
         acc,
         ctx
       )
       when is_atom(fun) and is_list(args) do
    acc = [remote_entry(parts, fun, length(args) + 1, meta) | acc]
    Enum.reduce(args, acc, fn n, a -> walk_calls(n, a, ctx) end)
  end

  defp walk_pipe_target({fun, meta, args}, acc, ctx)
       when is_atom(fun) and is_list(args) and is_binary(ctx) do
    acc = [local_entry(ctx, fun, length(args) + 1, meta) | acc]
    Enum.reduce(args, acc, fn n, a -> walk_calls(n, a, ctx) end)
  end

  defp walk_pipe_target(node, acc, ctx), do: walk_calls(node, acc, ctx)

  defp remote_entry(parts, fun, arity, meta) do
    %{
      target_module: parts |> Enum.map_join(".", &Atom.to_string/1),
      function: Atom.to_string(fun),
      arity: arity,
      line: meta[:line],
      column: meta[:column]
    }
  end

  defp local_entry(ctx_str, fun, arity, meta) do
    %{
      target_module: ctx_str,
      function: Atom.to_string(fun),
      arity: arity,
      line: meta[:line],
      column: meta[:column]
    }
  end

  defp resolve_call_aliases(calls, aliases) do
    calls
    |> Enum.map(fn call ->
      first = call.target_module |> String.split(".") |> List.first()

      case Map.get(aliases, first) do
        nil ->
          call

        full ->
          rest = call.target_module |> String.split(".") |> Enum.drop(1)
          resolved = [full | rest] |> Enum.join(".")
          %{call | target_module: resolved}
      end
    end)
    |> Enum.sort_by(&{&1.line, &1.column})
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  defp build_sup_node(pid) do
    info =
      Process.info(pid, [
        :dictionary,
        :initial_call,
        :status,
        :message_queue_len,
        :registered_name
      ])

    name =
      case info[:registered_name] do
        [] -> inspect(pid)
        n -> inspect(n)
      end

    mod =
      case info[:dictionary][:"$initial_call"] || info[:initial_call] do
        {m, _, _} -> m
        _ -> nil
      end

    is_sup = mod != nil and function_exported?(mod, :which_children, 1)

    children =
      if is_sup do
        try do
          for {_, child_pid, _, _} <- Supervisor.which_children(pid),
              is_pid(child_pid),
              Process.alive?(child_pid),
              do: build_sup_node(child_pid)
        rescue
          _ -> []
        end
      else
        []
      end

    %{
      pid: inspect(pid),
      name: name,
      module: inspect(mod),
      supervisor: is_sup,
      children: children,
      queue: info[:message_queue_len] || 0,
      status: to_string(info[:status] || :unknown)
    }
  end

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

  defp function_entry({kind, meta, [head | _]}) when is_atom(kind) do
    kind_str = Atom.to_string(kind)

    cond do
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
  defp function_head({name, _, args}) when is_list(args), do: {name, length(args)}
  defp function_head({name, _, _}), do: {name, 0}
  defp function_head(name) when is_atom(name), do: {name, 0}

  defp module_doc_info(mod) do
    try do
      case Code.fetch_docs(mod) do
        {:docs_v1, _, _, _, %{"en" => d}, _, docs} when d != "" -> {length(docs), true}
        {:docs_v1, _, _, _, _, _, docs} -> {length(docs), false}
        _ -> {0, false}
      end
    rescue
      _ -> {0, false}
    end
  end

  defp module_has_doc?(mod), do: module_doc_info(mod) |> elem(1)

  defp has_source?(mod), do: GtBridge.Resolve.source_file(mod) != nil

  defp with_xref(app, fun) do
    server = :"gt_xref_#{app}"

    case beam_path(app) do
      nil ->
        []

      path ->
        :xref.start(server)
        :xref.add_directory(server, path)
        result = fun.(server)
        :xref.stop(server)
        result
    end
  end

  defp beam_path(app) do
    Application.app_dir(app, "ebin") |> String.to_charlist()
  rescue
    _ -> nil
  end

  @doc """
  I hot-reload a source file and its dependents.

  1. Writes `content` to `path` and formats it
  2. Compiles the dep's full source tree via ParallelCompiler
     (excludes the currently running eval module)
  3. Persists compiled beams to ebin
  4. Recompiles the main project via IEx.Helpers.recompile

  Returns :ok.
  """
  @spec hot_reload(String.t(), String.t()) :: :ok
  def hot_reload(path, content) do
    File.write!(path, content)
    Mix.Tasks.Format.run([path])

    :ets.delete_all_objects(:elixir_modules)
    abs_path = Path.expand(path)

    compiled = Code.compile_file(path)
    # Any module from the file suffices — we only need the app.
    # (Files with typedstruct may return helper modules first.)
    [{mod, _} | _] = compiled
    app = Application.get_application(mod)
    main_app = Mix.Project.config()[:app]

    case app do
      nil ->
        # Standalone module — no app to persist into or propagate across.
        :ok

      ^main_app ->
        # Main project — IEx.recompile handles manifest-driven recompilation.
        :ok

      _ ->
        # Dependency — persist the directly compiled modules, then
        # compile all siblings in one pass for struct propagation.
        # Exclude __ENV__.file to avoid purging the running code.
        for {m, binary} <- compiled, do: persist_beam(m, binary)

        self_path = __ENV__.file |> Path.expand()

        siblings =
          app_source_files(app)
          |> Enum.reject(&(&1 in [abs_path, self_path]))

        {:ok, _mods, _} =
          Kernel.ParallelCompiler.compile(siblings,
            each_module: fn _file, m, binary -> persist_beam(m, binary) end
          )
    end

    IEx.Helpers.recompile()
    :ok
  end

  defp app_source_files(app) do
    {:ok, mods} = :application.get_key(app, :modules)
    mods |> Enum.map(&GtBridge.Resolve.source_file/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  defp persist_beam(mod, binary) do
    case Application.get_application(mod) do
      nil ->
        :skip

      app ->
        ebin = Application.app_dir(app, "ebin")
        File.mkdir_p!(ebin)
        File.write!(Path.join(ebin, "#{mod}.beam"), binary)
    end
  end

  @doc """
  I return the compile dependency graph as {from, to, label} edges.

  Edges represent: changing `to` forces recompilation of `from`.
  Label is :compile, :export, or :runtime.
  """
  @stdlib_modules MapSet.new([
                    Kernel,
                    Kernel.Typespec,
                    Kernel.Utils,
                    Module,
                    Protocol,
                    Application,
                    Supervisor,
                    GenServer,
                    Agent,
                    Task,
                    Enum,
                    String,
                    Map,
                    MapSet,
                    Keyword,
                    List,
                    Atom,
                    Integer,
                    IO,
                    File,
                    Path,
                    Code,
                    Logger
                  ])

  @spec compile_dep_edges(keyword()) :: [map()]
  def compile_dep_edges(opts \\ []) do
    manifest_path = Path.join(Mix.Project.manifest_path(), "compile.elixir")
    {_modules, sources} = Mix.Compilers.Elixir.read_manifest(manifest_path)
    include_stdlib? = Keyword.get(opts, :stdlib, false)
    app_filter = Keyword.get(opts, :app, nil)

    app_modules =
      if app_filter do
        case :application.get_key(app_filter, :modules) do
          {:ok, mods} -> MapSet.new(mods)
          _ -> nil
        end
      end

    internal? = Keyword.get(opts, :internal, false)

    for {_file, entry} <- sources,
        defined = elem(entry, 11),
        from <- defined,
        app_modules == nil or MapSet.member?(app_modules, from),
        {deps, label} <- [
          {elem(entry, 4), :compile},
          {elem(entry, 5), :export}
        ],
        to <- deps,
        to not in defined,
        include_stdlib? or not MapSet.member?(@stdlib_modules, to),
        not internal? or (app_modules != nil and MapSet.member?(app_modules, to)) do
      %{from: inspect(from), to: inspect(to), label: label}
    end
    |> Enum.uniq()
    |> Enum.sort_by(&{&1.from, &1.to})
  end
end
