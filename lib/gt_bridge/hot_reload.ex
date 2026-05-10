defmodule GtBridge.HotReload do
  @moduledoc """
  I drive the hot-reload pipeline: write source to disk, compile,
  persist beam files, broadcast events, and return a payload that
  GT-side subscribers can re-render from directly.

  See `reload/2` for the full sequence and the `recompiled` payload
  shape carried back to the GT side.
  """

  @doc """
  I hot-reload a source file and its dependents.

  1. Writes `content` to `path` and formats it
  2. Compiles the dep's full source tree via ParallelCompiler
     (excludes the currently running eval module)
  3. Persists compiled beams to ebin
  4. Recompiles the main project via IEx.Helpers.recompile
  5. Broadcasts a `%GtBridge.Events.ModuleEvent{kind: :recompiled}` for each
     module that was compiled. On parse/compile failure, broadcasts a
     `%ModuleEvent{kind: :compile_failed}` and reraises.

  Returns `%{recompiled: [payload]}` where each payload is a map. The
  directly-saved module's payload carries `mod`, `source_hash`, and
  `functions` (the new `Analysis.all_functions/1` result) inline, so
  GT-side subscribers re-render from the announcement without a
  follow-up bridge call. Sibling modules from ParallelCompiler
  propagation arrive bare (`%{mod: name, source_hash: nil, functions: nil}`)
  and let any subscribers fall back to refetching on demand.

  Module names are stripped of the `"Elixir."` prefix so GT-side
  handlers can match them against `ElixirModuleCoder >> moduleName`
  directly.
  """
  @spec reload(String.t(), String.t()) :: map()
  def reload(path, content) do
    # On success the result is `%{recompiled: [...]}`. Recompiled carries
    # the full `Analysis.all_functions/1` shape including default-arg
    # siblings and macro-generated entries.  On failure the result is
    # `%{source_written: %{...}, errors: [...]}`: disk has new bytes but
    # BEAM doesn't have the corresponding code, so subscribers re-derive
    # from the AST-only parse in `source_written`.  At most one of
    # `recompiled` / `source_written` is present in the result, so
    # subscribers don't need dedup.
    File.write!(path, content)

    {formatted, format_err} =
      case format_or_error(path) do
        {:ok, fmt} -> {fmt, nil}
        {:error, e} -> {content, e}
      end

    # Always broadcast :source_written so subscribers can re-baseline
    # against disk regardless of compile/format outcome.  When the
    # source doesn't parse, `functions` is [] (lenient parser couldn't
    # recover anything either).
    GtBridge.Events.broadcast(%GtBridge.Events.ModuleEvent{
      kind: :source_written,
      mod: parse_module_name(formatted),
      source_hash: :erlang.phash2(formatted),
      source: formatted,
      functions: GtBridge.Analysis.functions_in_source(formatted)
    })

    if format_err do
      compile_failure(path, formatted, [compile_error_payload(format_err)])
    else
      try do
        do_compile(path, formatted)
      rescue
        e in [CompileError, SyntaxError, TokenMissingError] ->
          compile_failure(path, formatted, [compile_error_payload(e)])
      end
    end
  end

  @spec format_or_error(String.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  defp format_or_error(path) do
    Mix.Tasks.Format.run([path])
    {:ok, File.read!(path)}
  rescue
    e in [SyntaxError, TokenMissingError] -> {:error, e}
  end

  defp compile_failure(path, content, errors) do
    GtBridge.Events.broadcast(%GtBridge.Events.ModuleEvent{
      kind: :compile_failed,
      mod: parse_module_name(content),
      errors: errors
    })

    Map.merge(source_written_payload(path, content), %{errors: errors})
  end

  defp parse_module_name(source) do
    case Regex.run(~r/^\s*defmodule\s+([A-Z][A-Za-z0-9_.]*)\b/m, source) do
      [_, name] -> Module.concat([name])
      _ -> nil
    end
  end

  # I do the compile + sibling propagation half. Pulled out of `reload/2`
  # so the disk-write half can run unconditionally and the compile half
  # can be wrapped in a try.
  defp do_compile(path, content) do
    :ets.delete_all_objects(:elixir_modules)
    abs_path = Path.expand(path)

    compiled = Code.compile_file(path)
    [{mod, _} | _] = compiled
    app = Application.get_application(mod)
    main_app = Mix.Project.config()[:app]

    sibling_mods =
      case app do
        nil ->
          []

        ^main_app ->
          []

        _ ->
          for {m, binary} <- compiled, do: persist_beam(m, binary)

          self_path = __ENV__.file |> Path.expand()

          siblings =
            app_source_files(app)
            |> Enum.reject(&(&1 in [abs_path, self_path]))

          {:ok, mods, _} =
            Kernel.ParallelCompiler.compile(siblings,
              each_module: fn _file, m, binary -> persist_beam(m, binary) end
            )

          mods
      end

    IEx.Helpers.recompile()
    broadcast_recompiled(compiled, sibling_mods, content)
    %{recompiled: recompiled_payloads(compiled, sibling_mods, content)}
  end

  defp source_written_payload(path, content) do
    %{
      source_written: %{
        source_path: path,
        source: content,
        source_hash: :erlang.phash2(content),
        functions: GtBridge.Analysis.functions_in_source(content)
      }
    }
  end

  # I build the per-module payload list returned by `reload/2`.
  # Direct (saved) module gets `functions` inline so GT's Functions
  # tab + |> expander can re-render without a follow-up bridge call.
  # Siblings stay bare — the directly-saved module is the only one
  # whose coder/streaming surface is guaranteed to be active in the
  # same view.
  defp recompiled_payloads(compiled, sibling_mods, content) do
    direct = for {m, _} <- compiled, do: enriched_payload(m, content)
    siblings = for m <- sibling_mods, do: bare_payload(m)
    direct ++ siblings
  end

  defp enriched_payload(mod, content) do
    %{
      mod: module_name(mod),
      source_hash: :erlang.phash2(content),
      functions: GtBridge.Analysis.all_functions(mod)
    }
  end

  defp bare_payload(mod) do
    %{mod: module_name(mod), source_hash: nil, functions: nil}
  end

  defp module_name(mod) do
    mod |> to_string() |> String.replace_prefix("Elixir.", "")
  end

  defp broadcast_recompiled(compiled, sibling_mods, content) do
    source_hash = :erlang.phash2(content)

    for {m, _} <- compiled do
      GtBridge.Events.broadcast(%GtBridge.Events.ModuleEvent{
        kind: :recompiled,
        mod: m,
        source_hash: source_hash
      })
    end

    for m <- sibling_mods do
      GtBridge.Events.broadcast(%GtBridge.Events.ModuleEvent{
        kind: :recompiled,
        mod: m
      })
    end

    :ok
  end

  defp compile_error_payload(e) do
    %{
      phase: error_phase(e),
      file: Map.get(e, :file),
      line: Map.get(e, :line),
      column: Map.get(e, :column),
      message: Exception.message(e)
    }
  end

  defp error_phase(%CompileError{}), do: :compile
  defp error_phase(%SyntaxError{}), do: :parse
  defp error_phase(%TokenMissingError{}), do: :parse

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
