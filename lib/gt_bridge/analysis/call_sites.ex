defmodule GtBridge.Analysis.CallSites do
  @moduledoc """
  I resolve call sites for GT's inline `|>` expander: which calls in
  a source buffer point at real functions or types, resolved through
  the context module's aliases, imports, and its own defs. Name-set
  and alias/import lookups are md5-cached per module.
  """

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
    with {:ok, ast} <- GtBridge.Analysis.Source.quoted(source) do
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
          GtBridge.Analysis.Source.source_function_names(source, ast),
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
      (GtBridge.Beam.info(mod, :functions) ++ GtBridge.Beam.info(mod, :macros))
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
    GtBridge.Analysis.all_functions(mod) |> Enum.any?(&(&1.name == name))
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
        case GtBridge.Analysis.Source.quoted(src) do
          {:ok, ast} -> GtBridge.Analysis.Source.source_function_names(src, ast)
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

  # I read the LoadedModules projection, not :application.get_key, so
  # modules created by a live recompile (a new file, or a nested module
  # from typedstruct module:) are enumerated instead of being frozen at
  # the boot-time app spec.
  # Read-through cache keyed by the module's md5: the key
  # self-invalidates on recompile and CacheReaper sweeps leftovers.
  defp cached_by_md5(tag, mod, fun) do
    GtBridge.CacheReaper.cached({tag, mod, GtBridge.Beam.info(mod, :md5)}, fun)
  end
end
