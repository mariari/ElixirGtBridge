defmodule GtBridge.Analysis.Graph do
  alias GtBridge.Analysis.LoadedModules

  @moduledoc """
  I answer the xref-backed graph questions: module dependency edges,
  callers and callees, implementors of a named function (with
  default-arg arities resolved to their defining clause), and call
  references across loaded applications.
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
    app_mods = MapSet.new(LoadedModules.modules_for_app(app))

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
  I return all modules that define a function with the given name and
  optional arity. Includes `def`, `defp`, and macro-generated functions.
  """
  @spec implementors(atom(), non_neg_integer() | nil) :: [map()]
  def implementors(name, arity \\ nil) do
    name_str = Atom.to_string(name)

    Application.loaded_applications()
    |> Enum.flat_map(fn {app, _, _} -> LoadedModules.modules_for_app(app) end)
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
    funs = GtBridge.Analysis.all_functions(mod)

    ast_entries =
      funs
      |> Enum.filter(&(&1.name == name_str and (arity == nil or &1.arity == arity)))
      |> Enum.map(&Map.put(&1, :module, mod_str))

    ast_arities = for e <- funs, e.name == name_str, into: MapSet.new(), do: e.arity

    exported_arities =
      for {n, a} <- GtBridge.Beam.info(mod, :functions), n == name_atom, do: a

    specs = GtBridge.Beam.specs_by_arity(mod)

    extra =
      for a <- exported_arities,
          arity == nil or a == arity,
          not MapSet.member?(ast_arities, a) do
        Map.put(
          GtBridge.Beam.runtime_stub(name_str, a, Map.get(specs, {name_atom, a})),
          :module,
          mod_str
        )
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
          GtBridge.Analysis.all_functions(from_mod)
          |> Enum.filter(fn f -> f.name == from_name and f.arity == from_ar end)
          |> Enum.map(&Map.put(&1, :module, inspect(from_mod)))
        end)
        |> Enum.sort_by(&{&1.module, &1.name})

      _ ->
        []
    end
  end
end
