defmodule GtBridge.Mix do
  @moduledoc """
  I am the shared mix-project introspection helpers used across
  hot_reload, module_creator, and code_monitor.

  ### Public API

  - `normalize_dep/1` — coerce any of mix's 4 dep shapes to `{app, opts}`.
  - `path_dep_apps/0` — just the app names of `path_deps/0`.
  - `path_dep_opts/1` — opts for a specific path-dep, or nil.
  """

  @type dep ::
          atom() | {atom(), keyword()} | {atom(), String.t(), keyword()} | {atom(), String.t()}

  @spec normalize_dep(dep()) :: {atom(), keyword()}
  def normalize_dep({app, opts}) when is_list(opts), do: {app, opts}
  def normalize_dep({app, _, opts}) when is_list(opts), do: {app, opts}
  def normalize_dep({app, _}), do: {app, []}
  def normalize_dep(app) when is_atom(app), do: {app, []}

  @spec path_deps() :: [{atom(), keyword()}]
  defp path_deps do
    for dep <- Mix.Project.config()[:deps] || [],
        {app, opts} = normalize_dep(dep),
        Keyword.has_key?(opts, :path),
        do: {app, opts}
  end

  @spec path_dep_apps() :: [atom()]
  def path_dep_apps, do: for({app, _} <- path_deps(), do: app)

  @spec path_dep_opts(atom()) :: keyword() | nil
  def path_dep_opts(app) do
    case List.keyfind(path_deps(), app, 0) do
      {^app, opts} -> opts
      nil -> nil
    end
  end
end
