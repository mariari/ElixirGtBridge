# credo:disable-for-this-file
defmodule GtBridge.Analysis do
  # mnesia is an optional runtime dependency — not available at compile time
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

  ############################################################
  #                   Private Implementation                 #
  ############################################################

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

  defp extract_functions({:defmodule, _, [_, [do: body]]}) do
    Enum.flat_map([body], &function_entry/1)
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
    case :code.lib_dir(app) do
      {:error, _} -> nil
      path -> Path.join(path, "ebin")
    end
  end
end
