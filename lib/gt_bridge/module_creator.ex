defmodule GtBridge.ModuleCreator do
  @moduledoc """
  I create a fresh Elixir source file for a module name and recompile.

  Used by the GT-side "+ Create module" button to materialize a missing
  module reference into an actual `.ex` file in the host project's
  `lib/` directory.

  ### Public API

  - `create/1` — write a `defmodule` skeleton at the path implied by
    the atom name and recompile through `GtBridge.HotReload`.
  """

  @doc """
  I write `defmodule <name> do; end` to the path implied by `name`
  (e.g. `Foo.Bar` → `lib/foo/bar.ex`, snake-cased per
  `Macro.underscore/1`), create any missing parent directories, and
  recompile via `GtBridge.HotReload.reload/2`.

  On success I return the reload result extended with `:path`:

      %{recompiled: [...], path: "lib/foo/bar.ex"}

  The `:recompiled` entries are the same shape as a normal save's
  payload, so GT-side callers can drive their cache update through
  the same `BeamEventAnnouncer announceRecompiledFrom:` flow they
  already use after `saveAndCompile` — without that, the GT side
  doesn't learn about the new module until the next save and the
  wrench stays visible.

  Errors:
  - `{:error, :exists}` — the target file already exists.
  - `{:error, :not_elixir_module}` — `name` is not an `Elixir.*` atom
    (Erlang atoms like `:gen_server` aren't Elixir modules).
  """
  @spec create(atom()) :: map() | {:error, :exists | :not_elixir_module}
  def create(name) when is_atom(name) do
    case to_string(name) do
      "Elixir." <> rest ->
        path = lib_path(rest)

        if File.exists?(path) do
          {:error, :exists}
        else
          File.mkdir_p!(Path.dirname(path))

          GtBridge.HotReload.reload(path, "defmodule #{inspect(name)} do\nend\n")
          |> Map.put(:path, path)
        end

      _ ->
        {:error, :not_elixir_module}
    end
  end

  defp lib_path(rest) do
    parts = rest |> String.split(".") |> Enum.map(&Macro.underscore/1)
    Path.join(["lib" | parts]) <> ".ex"
  end
end
