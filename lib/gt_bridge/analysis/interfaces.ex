defmodule GtBridge.Analysis.Interfaces do
  @moduledoc """
  I list the behaviours and protocols an application defines, each
  with the modules implementing it.

  A behaviour row carries its `@callback` specs and the implementors
  found among loaded modules; a protocol row carries its function
  list and its impls. Everything travels as plain values, so GT can
  render the interface -> implementor tree without round trips.

  ### Public API

  - `in_app/1`
  - `of_module/1`
  """

  alias GtBridge.Analysis.LoadedModules

  @doc """
  I return the behaviours and protocols defined by `app`'s modules.

  Implementors are searched across all loaded modules, so another
  application implementing one of `app`'s behaviours is listed too.
  """
  @spec in_app(atom()) :: [map()]
  def in_app(app) do
    index = behaviour_index()

    rows =
      for mod <- LoadedModules.modules_for_app(app),
          # The projection's current-app fallback can misattribute
          # preloaded erts modules; no app defines those.
          :code.which(mod) != :preloaded,
          Code.ensure_loaded?(mod),
          row = describe(mod, index),
          do: row

    Enum.sort_by(rows, & &1.name)
  end

  @doc """
  I return one module's interface facts: the behaviours and protocols
  it implements, and its own row (with implementors) when it is
  itself one.

  One pass over the code server, so a documentation tab can call me
  on demand without lag.
  """
  @spec of_module(module()) :: map()
  def of_module(mod) do
    Code.ensure_loaded(mod)

    {implementor_mods, protos_for} =
      Enum.reduce(:code.all_loaded(), {[], []}, fn {m, _}, {ims, pfs} ->
        ims = if mod in module_behaviours(m), do: [m | ims], else: ims

        pfs =
          if function_exported?(m, :__impl__, 1) and m.__impl__(:for) == mod,
            do: [m.__impl__(:protocol) | pfs],
            else: pfs

        {ims, pfs}
      end)

    implements =
      for b <- module_behaviours(mod), Code.ensure_loaded?(b) do
        callbacks = b.behaviour_info(:callbacks)

        %{
          kind: :behaviour,
          name: inspect(b),
          callback_names: sigs(callbacks),
          implements: implemented_sigs(mod, callbacks)
        }
      end ++
        for proto <- Enum.sort(Enum.uniq(protos_for)), Code.ensure_loaded?(proto) do
          %{
            kind: :protocol,
            name: inspect(proto),
            functions: sigs(proto.__protocol__(:functions))
          }
        end

    %{
      module: inspect(mod),
      implements: implements,
      defines: describe(mod, %{mod => implementor_mods})
    }
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  # defprotocol defines behaviour_info too, so protocols test first.
  defp describe(mod, index) do
    cond do
      function_exported?(mod, :__protocol__, 1) -> protocol(mod)
      function_exported?(mod, :behaviour_info, 1) -> behaviour(mod, index)
      true -> nil
    end
  end

  defp behaviour(mod, index) do
    callbacks = mod.behaviour_info(:callbacks)

    implementors =
      for m <- Map.get(index, mod, []) do
        %{module: inspect(m), source: source(m), implements: implemented_sigs(m, callbacks)}
      end

    %{
      kind: :behaviour,
      name: inspect(mod),
      callbacks: callback_specs(mod, callbacks),
      callback_names: sigs(callbacks),
      implementors: Enum.sort_by(implementors, & &1.module)
    }
  end

  defp protocol(mod) do
    %{
      kind: :protocol,
      name: inspect(mod),
      functions: sigs(mod.__protocol__(:functions)),
      impls: Enum.sort_by(impls(mod), & &1.for)
    }
  end

  defp sigs(pairs), do: for({n, a} <- Enum.sort(pairs), do: "#{n}/#{a}")

  defp implemented_sigs(m, callbacks),
    do: for({n, a} <- Enum.sort(callbacks), function_exported?(m, n, a), do: "#{n}/#{a}")

  # A consolidated protocol knows its types; an unconsolidated one is
  # reconstructed from the __impl__ marker on loaded impl modules.
  defp impls(proto) do
    case proto.__protocol__(:impls) do
      {:consolidated, types} ->
        for t <- types, m = Module.concat(proto, t) do
          %{for: inspect(t), module: inspect(m), source: source(m)}
        end

      :not_consolidated ->
        for {m, _} <- :code.all_loaded(),
            function_exported?(m, :__impl__, 1),
            m.__impl__(:protocol) == proto do
          %{for: inspect(m.__impl__(:for)), module: inspect(m), source: source(m)}
        end
    end
  end

  defp callback_specs(mod, callbacks) do
    specs =
      case Code.Typespec.fetch_callbacks(mod) do
        {:ok, cbs} -> Map.new(cbs)
        :error -> %{}
      end

    for {n, a} <- Enum.sort(callbacks) do
      case specs[{n, a}] do
        [spec | _] -> "@callback " <> Macro.to_string(Code.Typespec.spec_to_quoted(n, spec))
        _ -> "#{n}/#{a}"
      end
    end
  end

  # One pass over the code server: behaviour module => implementors.
  defp behaviour_index do
    Enum.reduce(:code.all_loaded(), %{}, fn {m, _}, acc ->
      Enum.reduce(module_behaviours(m), acc, fn b, inner ->
        Map.update(inner, b, [m], &[m | &1])
      end)
    end)
  end

  defp module_behaviours(m) do
    m.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()
  rescue
    _ -> []
  end

  defp source(m) do
    with true <- Code.ensure_loaded?(m),
         path when is_list(path) <- m.module_info(:compile)[:source] do
      List.to_string(path)
    else
      _ -> nil
    end
  end
end
