defmodule GtBridge.DepGraph do
  @moduledoc """
  I expose application-level dependency graph queries to GT.

  All queries skip infrastructure apps (`:kernel`, `:stdlib`,
  `:elixir`, `:compiler`, `:logger`) so the graph stays focused on
  the user's apps and their transitive dependencies.
  """

  @infrastructure_apps MapSet.new([:kernel, :stdlib, :elixir, :compiler, :logger])

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
end
