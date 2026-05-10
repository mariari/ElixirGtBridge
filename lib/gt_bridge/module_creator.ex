defmodule GtBridge.ModuleCreator do
  @moduledoc """
  I create a fresh Elixir source file for a module name and recompile.

  Used by the GT-side wrench "Create module" form to materialize a
  missing module reference into an actual `.ex` file under the
  chosen application's `lib/` directory.

  ### Public API

  - `create/1` — write the skeleton under the main project's `lib/`.
  - `create/2` — write under a specific app's `lib/` (path-deps land
    in `deps/<app>/lib/...`).
  - `project_apps/0` — apps the form's autocomplete offers.
  """

  @doc "I create the module under the main project's `lib/`."
  @spec create(atom()) :: map() | {:error, :exists | :not_elixir_module | :unknown_app}
  def create(name) when is_atom(name) do
    create(name, Mix.Project.config()[:app])
  end

  @doc """
  I write `defmodule <name> do; end` under the chosen app's `lib/`.
  Path-deps land in their checked-out source tree so changes propagate
  back to the dep.
  """
  @spec create(atom(), atom() | nil) ::
          map() | {:error, :exists | :not_elixir_module | :unknown_app}
  def create(name, app) when is_atom(name) and is_atom(app) do
    with "Elixir." <> rest <- to_string(name),
         {:ok, lib_dir} <- app_lib_dir(app) do
      path = lib_path(lib_dir, rest)

      if File.exists?(path) do
        {:error, :exists}
      else
        File.mkdir_p!(Path.dirname(path))

        template = "defmodule #{inspect(name)} do\n  def hello, do: :world\nend\n"

        GtBridge.HotReload.reload(path, template)
        %{path: path}
      end
    else
      {:error, :unknown_app} -> {:error, :unknown_app}
      _ -> {:error, :not_elixir_module}
    end
  end

  @doc """
  I list apps the form's autocomplete offers: the main project plus
  every top-level dep declared in mix.exs.  Returns `[atom()]`.
  """
  @spec project_apps() :: [atom()]
  def project_apps do
    main = Mix.Project.config()[:app]
    deps = for dep <- Mix.Project.config()[:deps] || [], do: elem(GtBridge.Mix.normalize_dep(dep), 0)
    [main | deps] |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  # Path-deps land in their checked-out tree; everything else writes
  # into `deps/<app>/lib` (which Mix unpacks during `deps.get`).  Hex
  # / git deps will get overwritten by the next `mix deps.compile` if
  # they aren't path-linked, but writing there is what the user asked
  # for when picking that app.
  defp app_lib_dir(app) do
    cond do
      app == Mix.Project.config()[:app] -> {:ok, "lib"}
      dep = GtBridge.Mix.path_dep_opts(app) -> {:ok, Path.join(dep[:path], "lib")}
      declared_dep?(app) -> {:ok, Path.join(["deps", to_string(app), "lib"])}
      true -> {:error, :unknown_app}
    end
  end

  defp declared_dep?(app) do
    Enum.any?(Mix.Project.config()[:deps] || [], fn dep ->
      elem(GtBridge.Mix.normalize_dep(dep), 0) == app
    end)
  end

  defp lib_path(lib_dir, rest) do
    parts = rest |> String.split(".") |> Enum.map(&Macro.underscore/1)
    Path.join([lib_dir | parts]) <> ".ex"
  end
end
