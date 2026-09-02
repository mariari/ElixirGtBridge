defmodule GtBridge.Beam do
  @moduledoc """
  I read beam-file chunks directly.

  `Code.fetch_docs/1` pulls the whole object code through
  `:code.get_object_code/1`; seeking to the one chunk is ~2.7x
  cheaper (851us -> 319us for Enum), and doc reads happen on every
  dot keystroke and on app-wide coverage sweeps.

  ### Public API

  - `defined_names/1`
  - `docs/1`
  - `info/2`
  - `runtime_stub/3`
  - `specs_by_arity/1`
  """

  @doc "I return the `docs_v1` chunk term for `module`, or `:error`."
  @spec docs(module()) :: tuple() | :error
  def docs(module) do
    with path when is_list(path) <- :code.which(module),
         {:ok, {_, [{_, raw}]}} <- :beam_lib.chunks(path, [~c"Docs"]) do
      :erlang.binary_to_term(raw)
    else
      _ -> :error
    end
  end

  @doc """
  I return `mod.__info__(kind)` or `[]`: `__info__/1` can raise for
  some macro-only modules despite exporting it.
  """
  @spec info(module(), atom()) :: term()
  def info(mod, kind) do
    if function_exported?(mod, :__info__, 1) do
      try do
        mod.__info__(kind)
      rescue
        _ in [UndefinedFunctionError, ArgumentError] -> []
      end
    else
      []
    end
  end

  @doc """
  I return %{{name, arity} => formatted_spec_string} for every
  function the BEAM has a typespec for; used to enrich
  macro-generated entries that have no source.
  """
  @spec specs_by_arity(module()) :: %{{atom(), arity()} => String.t()}
  def specs_by_arity(mod) do
    case Code.Typespec.fetch_specs(mod) do
      {:ok, specs} ->
        Map.new(specs, fn {{name, arity}, [spec | _]} ->
          formatted = Code.Typespec.spec_to_quoted(name, spec) |> Macro.to_string()
          {{name, arity}, formatted}
        end)

      _ ->
        %{}
    end
  end

  @doc "I return every function `module` defines, private ones included."
  @spec defined_names(module()) :: [String.t()]
  def defined_names(module) do
    with path when is_list(path) <- :code.which(module),
         {:ok, {_, [abstract_code: {_, forms}]}} <-
           :beam_lib.chunks(path, [:abstract_code]) do
      for {:function, _, name, _arity, _} <- forms,
          do: name |> Atom.to_string() |> String.replace_prefix("MACRO-", "")
    else
      _ -> []
    end
  end

  @doc """
  The shape of an exports-only entry: a runtime function with no
  textual def, carrying a synthesized source (with an @spec line
  when the BEAM knows one).
  """
  @spec runtime_stub(String.t(), arity(), String.t() | nil) :: map()
  def runtime_stub(name_str, arity, spec) do
    %{
      name: name_str,
      arity: arity,
      kind: :def,
      start: 0,
      end_line: 0,
      sig: "#{name_str}/#{arity}",
      source: synth_no_source(name_str, arity, spec)
    }
  end

  defp synth_no_source(name_str, arity, nil),
    do: "# #{name_str}/#{arity}, no source"

  defp synth_no_source(name_str, arity, spec_string),
    do: "@spec #{spec_string}\n# #{name_str}/#{arity}, no source"
end
