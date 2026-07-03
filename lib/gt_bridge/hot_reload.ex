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

  Returns `%{recompiled: [payload]}` where each payload is a map. Every
  module compiled from the saved file carries `mod`, `source_hash`, and
  `functions` (the `Analysis.all_functions/1` result, scoped to that
  module) inline, so each module's GT-side cache re-renders from the
  announcement without a follow-up bridge call. A sibling or nested
  module gets refreshed too, not just the file's first module. Modules
  from ParallelCompiler propagation of *other* files arrive bare
  (`%{mod: name, source_hash: nil, functions: nil}`)
  and let any subscribers fall back to refetching on demand.

  Returns `:ok` regardless of success/failure; subscribers learn the
  outcome via the broadcast events (`:source_written`, `:recompiled`,
  `:compile_failed`).  No GT-side caller inspects the response.
  """
  @spec reload(String.t(), String.t()) :: :ok
  def reload(path, content) do
    previous = read_source(path)
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
      mod: module_atom_in_source(formatted),
      source_hash: :erlang.phash2(formatted),
      source: formatted,
      functions: GtBridge.Analysis.functions_in_source(formatted)
    })

    if format_err do
      broadcast_compile_failure(formatted, [compile_error_payload(format_err)])
    else
      try do
        do_compile(path, formatted, previous)
      rescue
        e in [CompileError, SyntaxError, TokenMissingError] ->
          broadcast_compile_failure(formatted, [compile_error_payload(e)])
      catch
        {:gt_compile_failed, errors} ->
          broadcast_compile_failure(formatted, errors)
      end
    end

    :ok
  end

  @spec format_or_error(String.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  defp format_or_error(path) do
    Mix.Tasks.Format.run([path])
    {:ok, File.read!(path)}
  rescue
    e in [SyntaxError, TokenMissingError] -> {:error, e}
  end

  defp broadcast_compile_failure(content, errors) do
    GtBridge.Events.broadcast(%GtBridge.Events.ModuleEvent{
      kind: :compile_failed,
      mod: module_atom_in_source(content),
      errors: errors
    })
  end

  defp module_atom_in_source(source) do
    case GtBridge.Analysis.module_in_source(source) do
      nil -> nil
      name -> Module.concat([name])
    end
  end

  # I do the compile + sibling propagation half. Pulled out of `reload/2`
  # so the disk-write half can run unconditionally and the compile half
  # can be wrapped in a try. `previous` is the file's pre-save source,
  # used to detect modules this save removed.
  defp do_compile(path, content, previous) do
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

          parallel_compile_or_throw(siblings)
      end

    recompile_preserving_modules()
    purge_removed_modules(compiled, previous)
    broadcast_recompiled(compiled, sibling_mods, content)
  end

  # The compile result is the file's complete module set, so a module
  # the previous source defined but absent from it was removed by this
  # save. Purge it instead of leaving a ghost in the module list.
  @spec purge_removed_modules([{module(), binary()}], String.t() | nil) :: :ok
  defp purge_removed_modules(_, nil), do: :ok

  defp purge_removed_modules(compiled, previous) do
    current = MapSet.new(compiled, fn {m, _} -> m end)

    for name <- GtBridge.Analysis.modules_in_source(previous),
        m = Module.concat([name]),
        not MapSet.member?(current, m) do
      purge_module(m)
    end

    :ok
  end

  # Mix's failed retry purges the module being compiled and may delete
  # its .beam.  Snapshot bytecode in memory before, restore via
  # load_binary after.
  defp recompile_preserving_modules do
    snapshot = snapshot_project_modules()

    try do
      recompile_or_throw()
    after
      for {m, file, beam} <- snapshot, :code.is_loaded(m) == false do
        :code.load_binary(m, file, beam)
      end
    end
  end

  defp snapshot_project_modules do
    apps = [Mix.Project.config()[:app] | GtBridge.Mix.path_dep_apps()] |> Enum.reject(&is_nil/1)

    for app <- apps,
        {:ok, mods} <- [:application.get_key(app, :modules)],
        m <- mods,
        {^m, beam, file} <- [safe_get_object_code(m)] do
      {m, file, beam}
    end
  end

  defp safe_get_object_code(m) do
    case :code.get_object_code(m) do
      {^m, _beam, _file} = ok -> ok
      _ -> nil
    end
  end

  defp recompile_or_throw do
    if mix_started?() do
      Mix.Project.with_build_lock(fn ->
        maybe_purge_mix_listener()
        diagnostics = run_mix_compile_capturing_diagnostics()
        errors = Enum.filter(diagnostics, &(Map.get(&1, :severity) == :error))

        if errors != [] do
          throw({:gt_compile_failed, Enum.map(errors, &diagnostic_error_payload/1)})
        end
      end)
    end
  end

  defp mix_started? do
    List.keyfind(Application.started_applications(), :mix, 0) != nil
  end

  defp maybe_purge_mix_listener do
    if Code.ensure_loaded?(IEx.MixListener) and
         function_exported?(IEx.MixListener, :purge, 0) do
      IEx.MixListener.purge()
    end
  end

  defp run_mix_compile_capturing_diagnostics do
    config = Mix.Project.config()
    consolidation = Mix.Project.consolidation_path(config)

    Mix.Task.reenable("compile")
    Mix.Task.reenable("compile.all")
    Mix.Task.reenable("compile.protocols")
    compilers = config[:compilers] || Mix.compilers()
    Enum.each(compilers, &Mix.Task.reenable("compile.#{&1}"))

    args = ["--purge-consolidation-path-if-stale", consolidation, "--return-errors"]

    case Mix.Task.run("compile", args) do
      {_status, diagnostics} when is_list(diagnostics) -> diagnostics
      _ -> []
    end
  end

  defp diagnostic_error_payload(%{file: file, position: position, message: message}) do
    {line, column} =
      case position do
        {l, c} -> {l, c}
        n when is_integer(n) -> {n, nil}
        _ -> {nil, nil}
      end

    file_str = file && to_string(file)
    source = file_str && read_source(file_str)
    enclosing = source && line && enclosing_function(source, line)

    %{
      phase: :compile,
      file: file_str,
      line: line,
      column: column,
      message: to_string(message),
      module: source && GtBridge.Analysis.module_in_source(source),
      function: enclosing && enclosing.name,
      arity: enclosing && enclosing.arity
    }
  end

  # I compile a list of files via ParallelCompiler so verifier errors
  # come back structured (`{:error, errors, _}`) instead of raising
  # `CompileError` with just a wrapper message.  Throw the structured
  # errors so reload's catch-clause builds the failure shape with
  # file/line/column preserved per error.  Used uniformly for the
  # save target and for cascade siblings.
  defp parallel_compile_or_throw(paths) do
    case Kernel.ParallelCompiler.compile(paths,
           each_module: fn _file, m, binary -> persist_beam(m, binary) end
         ) do
      {:ok, mods, _warnings} -> mods
      {:error, errors, _warnings} -> throw_verifier_errors(errors)
    end
  end

  defp throw_verifier_errors(errors) do
    throw({:gt_compile_failed, Enum.map(errors, &verifier_error_payload/1)})
  end

  defp verifier_error_payload({file, {line, column}, message}),
    do: build_error_payload(file, line, column, message)

  defp verifier_error_payload({file, line, message}) when is_integer(line),
    do: build_error_payload(file, line, nil, message)

  defp verifier_error_payload({file, _, message}),
    do: build_error_payload(file, nil, nil, message)

  defp build_error_payload(file, line, column, message) do
    file_str = to_string(file)
    source = read_source(file_str)
    enclosing = source && line && enclosing_function(source, line)

    %{
      phase: :compile,
      file: file_str,
      line: line,
      column: column,
      message: to_string(message),
      module: source && GtBridge.Analysis.module_in_source(source),
      function: enclosing && enclosing.name,
      arity: enclosing && enclosing.arity
    }
  end

  defp read_source(nil), do: nil

  defp read_source(file) do
    case File.read(file) do
      {:ok, content} -> content
      _ -> nil
    end
  end

  defp enclosing_function(source, line) do
    GtBridge.Analysis.functions_in_source(source)
    |> Enum.find(fn f -> f.start <= line and line <= f.end_line end)
  end

  defp broadcast_recompiled(compiled, sibling_mods, content) do
    source_hash = :erlang.phash2(content)

    for {m, _} <- compiled do
      GtBridge.Events.broadcast(%GtBridge.Events.ModuleEvent{
        kind: :recompiled,
        mod: m,
        source_hash: source_hash,
        functions: GtBridge.Analysis.all_functions(m)
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
    file = Map.get(e, :file)
    line = Map.get(e, :line)
    source = file && read_source(file)
    enclosing = source && line && enclosing_function(source, line)

    %{
      phase: error_phase(e),
      file: file,
      line: line,
      column: Map.get(e, :column),
      message: Exception.message(e),
      module: source && GtBridge.Analysis.module_in_source(source),
      function: enclosing && enclosing.name,
      arity: enclosing && enclosing.arity
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

  @doc """
  I drop `mod` from the BEAM so a stale loaded copy does not survive
  source-file deletion, then broadcast `:source_removed`.  GT-side
  caches subscribe to that event and drop their derived state.
  """
  @spec purge_module(module()) :: :ok
  def purge_module(mod) when is_atom(mod) do
    # Delete the beam too, or Code.ensure_loaded? resurrects the
    # ghost from ebin.
    case :code.which(mod) do
      path when is_list(path) -> File.rm(List.to_string(path))
      _ -> :ok
    end

    :code.purge(mod)
    :code.delete(mod)

    GtBridge.Events.broadcast(%GtBridge.Events.ModuleEvent{
      kind: :source_removed,
      mod: mod
    })

    :ok
  end

  @doc """
  I return the compile dependency graph as {from, to, label} edges.

  Edges represent: changing `to` forces recompilation of `from`.
  Label is :compile, :export, or :runtime.
  """
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
