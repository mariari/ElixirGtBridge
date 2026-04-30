defmodule GtBridge.Analysis do
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

      pairs
      |> Enum.map(fn {{from, _, _}, {to, _, _}} -> {from, to} end)
      |> Enum.uniq()
      |> Enum.filter(fn {from, to} -> from != to end)
    end)
  end

  @doc "I return the modules that `mod` calls."
  @spec callees(module()) :: [module()]
  def callees(mod) do
    app = Application.get_application(mod)
    if app, do: callees(mod, app), else: []
  end

  @doc "I return the modules that `mod` calls within `app`."
  @spec callees(module(), atom()) :: [module()]
  def callees(mod, app) do
    module_graph(app)
    |> Enum.filter(fn {from, _} -> from == mod end)
    |> Enum.map(&elem(&1, 1))
  end

  @doc "I return the modules within `app` that call `mod`."
  @spec callers(module(), atom()) :: [module()]
  def callers(mod, app) do
    module_graph(app)
    |> Enum.filter(fn {_, to} -> to == mod end)
    |> Enum.map(&elem(&1, 0))
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
    {total_mods, total_fns, with_docs, with_source} =
      Enum.reduce(Application.loaded_applications(), {0, 0, 0, 0}, fn {app, _, _}, acc ->
        modules(app)
        |> Enum.reduce(acc, fn mod, {m, f, d, s} ->
          {fun_count, has_doc} =
            try do
              case Code.fetch_docs(mod) do
                {:docs_v1, _, _, _, %{"en" => doc}, _, ds} when doc != "" -> {length(ds), 1}
                {:docs_v1, _, _, _, _, _, ds} -> {length(ds), 0}
                _ -> {0, 0}
              end
            rescue
              _ -> {0, 0}
            end

          has_src =
            try do
              if mod.module_info(:compile)[:source] != nil, do: 1, else: 0
            rescue
              _ -> 0
            end

          {m + 1, f + fun_count, d + has_doc, s + has_src}
        end)
      end)

    %{
      apps: length(Application.loaded_applications()),
      modules: total_mods,
      functions: total_fns,
      with_docs: with_docs,
      with_source: with_source
    }
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
      has_mod_doc = module_has_doc?(mod)

      funs =
        try do
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

      %{module: inspect(mod), has_mod_doc: has_mod_doc, functions: funs}
    end)
    |> Enum.sort_by(& &1.module)
  end

  @doc """
  I return all function definitions (def and defp) with line ranges.

  Parses the source AST to find all function clauses including
  private functions that `Code.fetch_docs/1` doesn't cover.
  """
  @spec all_functions(module()) :: [map()]
  def all_functions(mod) do
    with path when is_binary(path) <- GtBridge.Resolve.source_file(mod),
         {:ok, source} <- File.read(path),
         {:ok, ast} <- Code.string_to_quoted(source, columns: true, token_metadata: true) do
      extract_functions(ast)
    else
      _ -> []
    end
  end

  @doc """
  I return a nested supervision tree starting from a PID.

  Each node is a map with `:pid`, `:name`, `:module`, `:supervisor`,
  `:children`, `:queue`, and `:status`. Large worker pools appear
  as-is — GT collapses them during rendering.
  """
  @spec supervision_tree(pid()) :: map()
  def supervision_tree(pid) when is_pid(pid), do: build_sup_node(pid)

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  defp build_sup_node(pid) do
    info = Process.info(pid, [:dictionary, :initial_call, :status, :message_queue_len, :registered_name])

    name =
      case info[:registered_name] do
        [] -> inspect(pid)
        n -> inspect(n)
      end

    mod =
      case info[:dictionary][:"$initial_call"] do
        {m, _, _} ->
          m

        _ ->
          case info[:initial_call] do
            {m, _, _} -> m
            _ -> nil
          end
      end

    is_sup = mod != nil and function_exported?(mod, :which_children, 1)

    children =
      if is_sup do
        try do
          Supervisor.which_children(pid)
          |> Enum.map(fn {_id, child_pid, _type, _mods} ->
            if is_pid(child_pid) and Process.alive?(child_pid),
              do: build_sup_node(child_pid)
          end)
          |> Enum.reject(&is_nil/1)
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

  defp extract_functions({:defmodule, _, [_, [do: {:__block__, _, body}]]}),
    do: extract_functions_from_body(body)

  # A do-block with a single expression is not wrapped in `:__block__`,
  # so `defmodule Foo do def hello, do: :world end` lands here.
  defp extract_functions({:defmodule, _, [_, [do: body]]}),
    do: extract_functions_from_body([body])

  defp extract_functions(_), do: []

  defp extract_functions_from_body(body) do
    body
    |> Enum.filter(fn
      {kind, _, _} when kind in [:def, :defp] -> true
      _ -> false
    end)
    |> Enum.map(fn {kind, meta, [head | _]} ->
      {name, arity} = function_head(head)
      end_line = meta[:end][:line] || meta[:end_of_expression][:line] || meta[:line]

      %{
        name: Atom.to_string(name),
        arity: arity,
        kind: Atom.to_string(kind),
        start: meta[:line],
        end_line: end_line,
        sig: "#{name}/#{arity}"
      }
    end)
  end

  defp function_head({:when, _, [head | _]}), do: function_head(head)
  defp function_head({name, _, args}) when is_list(args), do: {name, length(args)}
  defp function_head({name, _, _}), do: {name, 0}

  defp module_has_doc?(mod) do
    try do
      match?({:docs_v1, _, _, _, %{"en" => d}, _, _} when d != "", Code.fetch_docs(mod))
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
    case :code.lib_dir(app, :ebin) do
      {:error, _} -> nil
      path -> path
    end
  end
end
