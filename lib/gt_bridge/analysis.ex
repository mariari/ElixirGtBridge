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
  - `doc_coverage/1` — documentation status per module in an app
  """

  @type edge :: {module(), module()}
  @type doc_status :: :full | :partial | :none
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
  I return documentation coverage for each module in an application.

  Status is `:full` if the module has a non-empty `@moduledoc`,
  `:partial` if docs exist but `@moduledoc` is empty/hidden,
  `:none` if `Code.fetch_docs/1` fails.
  """
  @spec doc_coverage(atom()) :: [{module(), doc_status()}]
  def doc_coverage(app) do
    modules(app)
    |> Enum.map(fn mod -> {mod, module_doc_status(mod)} end)
    |> Enum.sort_by(fn {mod, _} -> inspect(mod) end)
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
  rescue
    _ -> []
  end

  @doc """
  I return all function definitions with complete line ranges.

  Each entry includes `:start` (extended back to include @doc/@spec),
  `:end_line`, `:name`, `:arity`, `:kind`, `:sig`, and `:source`
  (the source text for that function including annotations).

  The walk-back logic handles multiline @doc heredocs.
  """
  @spec all_functions(module()) :: [map()]
  def all_functions(mod) do
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

  @doc """
  I load module imports into an existing eval session. Unlike
  editor_session/2, I never create the session — if it doesn't
  exist, I return nil. Use this for snippet sessions where the
  session must be created by the HTTP handler (with the port
  for async result callbacks).
  """
  @spec preload_imports(module(), String.t()) :: String.t() | nil
  def preload_imports(mod, sid) do
    case Registry.lookup(GtBridge.EvalRegistry, sid) do
      [{pid, _}] when is_pid(pid) ->
        if Process.alive?(pid) do
          load_imports(mod, pid)
          sid
        end

      _ ->
        nil
    end
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

  defp preamble_directives(source) do
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

      try do
        exported_functions(mod)
        |> Enum.map(fn f -> Map.put(f, :module, mod_name) end)
      rescue
        _ -> []
      end
    end)
    |> Enum.filter(fn f ->
      String.contains?(String.downcase(f.name), q) or
        String.contains?(String.downcase(f.module), q)
    end)
    |> Enum.sort_by(&"#{&1.module}.#{&1.name}/#{&1.arity}")
    |> Enum.take(max)
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
          attrs:
            Enum.map_join(:mnesia.table_info(t, :attributes), ", ", &Atom.to_string/1)
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

  @directives [:@, :use, :import, :alias, :require]

  defp extract_functions({:defmodule, _, [_, [do: {:__block__, _, body}]]}) do
    Enum.flat_map(body, &function_entry/1)
  end

  defp extract_functions(_), do: []

  defp function_entry({kind, _, _}) when kind in @directives, do: []

  defp function_entry({kind, meta, [head | _]}) do
    {name, arity} = function_head(head)
    end_line = meta[:end][:line] || meta[:end_of_expression][:line] || meta[:line]

    [
      %{
        name: Atom.to_string(name),
        arity: arity,
        kind: Atom.to_string(kind),
        start: meta[:line],
        end_line: end_line,
        sig: "#{name}/#{arity}"
      }
    ]
  rescue
    _ -> []
  end

  defp function_entry(_), do: []

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

  defp has_source?(mod) do
    try do
      mod.module_info(:compile)[:source] != nil
    rescue
      _ -> false
    end
  end

  defp module_doc_status(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} when doc != "" -> :full
      {:docs_v1, _, _, _, :none, _, _} -> :none
      {:docs_v1, _, _, _, _, _, _} -> :partial
      _ -> :none
    end
  end

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

    # Ensure clean compiler state — previous compilations may
    # have left entries in this table.
    :ets.delete_all_objects(:elixir_modules)

    abs_path = Path.expand(path)
    [{mod, _} | _] = Code.compile_file(path)
    app = Application.get_application(mod)

    if app != Mix.Project.config()[:app] do
      # Dep: compile siblings for struct caller tracking.
      # Exclude the changed file and the calling module's file
      # to avoid triple-loading (which purges the running code).
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

    mods
    |> Enum.flat_map(fn m ->
      try do
        [m.__info__(:compile)[:source] |> List.to_string()]
      rescue
        _ -> []
      end
    end)
    |> Enum.uniq()
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
  I return compile dependency data from the project's manifest.

  Each entry has the source file, its defined modules, and three
  dependency lists: compile (macro/attribute deps that trigger
  recompilation), export (struct deps), and runtime (function calls).
  """
  @spec compile_deps() :: [map()]
  def compile_deps do
    manifest_path = Path.join(Mix.Project.manifest_path(), "compile.elixir")
    {_modules, sources} = Mix.Compilers.Elixir.read_manifest(manifest_path)

    for {file, entry} <- sources do
      %{
        file: file,
        modules: elem(entry, 11) |> Enum.map(&inspect/1),
        compile: elem(entry, 4) |> Enum.map(&inspect/1),
        export: elem(entry, 5) |> Enum.map(&inspect/1),
        runtime: elem(entry, 6) |> Enum.map(&inspect/1)
      }
    end
    |> Enum.sort_by(& &1.file)
  end

  @doc """
  I return the compile dependency graph as {from, to, label} edges.

  Edges represent: changing `to` forces recompilation of `from`.
  Label is :compile, :export, or :runtime.
  """
  @stdlib_modules MapSet.new([
    Kernel, Kernel.Typespec, Kernel.Utils, Module, Protocol,
    Application, Supervisor, GenServer, Agent, Task,
    Enum, String, Map, MapSet, Keyword, List, Atom, Integer,
    IO, File, Path, Code, Logger
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

  @doc """
  I return compile dependency edges reachable from a specific module.

  Transitively follows edges in both directions: upstream (what
  would cause this module to recompile) and downstream (what
  recompiles when this module changes).
  """
  @spec compile_dep_edges_for(module()) :: [map()]
  def compile_dep_edges_for(mod) do
    mod_name = inspect(mod)
    edges = compile_dep_edges()

    {up, down} =
      Enum.reduce(edges, {%{}, %{}}, fn e, {u, d} ->
        {Map.update(u, e.from, [e.to], &[e.to | &1]),
         Map.update(d, e.to, [e.from], &[e.from | &1])}
      end)

    reachable =
      bfs(MapSet.new([mod_name]), [mod_name], up)
      |> bfs([mod_name], down)

    Enum.filter(edges, &(MapSet.member?(reachable, &1.from) and MapSet.member?(reachable, &1.to)))
  end

  defp bfs(visited, [], _adj), do: visited

  defp bfs(visited, frontier, adj) do
    next = Enum.flat_map(frontier, &Map.get(adj, &1, [])) |> Enum.uniq() |> Enum.reject(&(&1 in visited))
    bfs(MapSet.union(visited, MapSet.new(next)), next, adj)
  end
end
