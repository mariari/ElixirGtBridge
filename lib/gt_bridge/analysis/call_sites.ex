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

  Sibling sources (other snippets on the same Lepiter page) contribute
  their `alias`/`import` directives and their function definitions,
  each parsed on its own, so a snippet that does not parse costs only
  its own contribution.
  """
  @spec call_sites(String.t(), module() | nil, [String.t()]) :: [map()]
  def call_sites(source, context_module \\ nil, sibling_sources \\ []) do
    source = normalize_line_endings(source)
    siblings = Enum.map(sibling_sources, &normalize_line_endings/1)

    GtBridge.CacheReaper.cached(
      {:call_sites, context_module, :erlang.phash2({source, siblings})},
      fn -> compute_call_sites(source, context_module, siblings) end
    )
  end

  # Smalltalk text uses CR (\r, 0x0D) as line separator while
  # Code.string_to_quoted only recognizes \n (and \r\n) — lone \r
  # leaves the whole source on a single line as far as the
  # tokenizer is concerned, so multi-line snippets returned []
  # call sites and the editor showed no |> triangles.  Normalize
  # all common variants to \n before hashing/parsing so
  # semantically-equivalent sources cache to the same key.
  defp normalize_line_endings(source) do
    source |> String.replace("\r\n", "\n") |> String.replace("\r", "\n")
  end

  defp compute_call_sites(source, context_module, siblings) do
    with {:ok, ast} <- GtBridge.Analysis.Source.quoted(source) do
      directives = GtBridge.Analysis.Source.directives(ast)
      env = if context_module, do: module_env(context_module), else: empty_env()
      sibling_asts = Enum.flat_map(siblings, &parseable_ast/1)

      sibling_directives =
        Enum.flat_map(sibling_asts, fn {_src, sibling_ast} ->
          GtBridge.Analysis.Source.directives(sibling_ast)
        end)

      # Closest declaration wins: source > siblings > context module.
      aliases =
        env.aliases
        |> Map.merge(GtBridge.Analysis.Walker.alias_map(sibling_directives))
        |> Map.merge(GtBridge.Analysis.Walker.alias_map(directives))

      imports =
        env.imports
        |> Map.merge(GtBridge.Analysis.Walker.import_map(sibling_directives))
        |> Map.merge(GtBridge.Analysis.Walker.import_map(directives))

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

      sibling_names =
        Enum.reduce(sibling_asts, MapSet.new(), fn {src, sibling_ast}, acc ->
          MapSet.union(acc, GtBridge.Analysis.Source.source_function_names(src, sibling_ast))
        end)

      local_names =
        GtBridge.Analysis.Source.source_function_names(source, ast)
        |> MapSet.union(sibling_names)
        |> MapSet.union(
          if(context_module,
            do: MapSet.union(exported_names(context_str), env.locals),
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

  defp parseable_ast(src) do
    case GtBridge.Analysis.Source.quoted(src) do
      {:ok, ast} -> [{src, ast}]
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
    aliases = module_env(context_module).aliases
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

  # One md5-cached parse of the module's saved source answers the trio
  # every resolution needs: its alias map, import map, and own def/type
  # names (parsing is ~3ms; the key self-invalidates on recompile).
  defp module_env(mod) do
    cached_by_md5(:module_env, mod, fn ->
      GtBridge.Resolve.with_source(mod, empty_env(), fn src ->
        case GtBridge.Analysis.Source.quoted(src) do
          {:ok, ast} ->
            directives = GtBridge.Analysis.Source.directives(ast, inspect(mod))

            %{
              aliases: GtBridge.Analysis.Walker.alias_map(directives),
              imports: GtBridge.Analysis.Walker.import_map(directives),
              locals: GtBridge.Analysis.Source.source_function_names(src, ast)
            }

          _ ->
            empty_env()
        end
      end)
    end)
  end

  defp empty_env, do: %{aliases: %{}, imports: %{}, locals: MapSet.new()}

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
    module_env(mod).aliases |> Enum.map(fn {short, full} -> [short, full] end)
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
