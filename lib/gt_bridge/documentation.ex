defmodule GtBridge.Documentation do
  @moduledoc """
  I provide structured access to Elixir module and function documentation.

  I extract docs via `Code.fetch_docs/1` and format them for rendering
  in GT's inspector — either as Phlow views (proxy inspection) or as a
  section-delimited string that GT splits into a `LePage`.

  ### Public API

  - `for_module/1` — documentation struct for a module
  - `for_function/2` — documentation for all arities of a function
  - `for_function/3` — documentation for a specific arity
  - `for_type/3` — documentation for a specific type
  - `to_sections/1` — section-delimited string for GT LePage rendering
  """

  use TypedStruct
  use GtBridge.View

  alias GtBridge.Phlow.{Text, ColumnedList}

  @type module_query :: {:module, module()}
  @type function_query :: {:function, module(), atom()}
  @type function_arity_query ::
          {:function, module(), atom(), non_neg_integer()}
  @type type_query :: {:type, module(), atom(), non_neg_integer()}
  @type query ::
          module_query()
          | function_query()
          | function_arity_query()
          | type_query()

  typedstruct do
    field(:query, query())
  end

  @spec for_module(module()) :: t()
  def for_module(module), do: %__MODULE__{query: {:module, module}}

  @spec for_function(module(), atom()) :: t()
  def for_function(module, function),
    do: %__MODULE__{query: {:function, module, function}}

  @spec for_function(module(), atom(), non_neg_integer()) :: t()
  def for_function(module, function, arity),
    do: %__MODULE__{query: {:function, module, function, arity}}

  @spec for_type(module(), atom(), non_neg_integer()) :: t()
  def for_type(module, name, arity),
    do: %__MODULE__{query: {:type, module, name, arity}}

  @doc """
  I return a single string with `__SECTION__` delimiters between snippets.

  GT splits on this delimiter and builds a `LePage` with one
  `LeTextSnippet` per section.
  """
  @spec to_sections(t()) :: String.t()
  def to_sections(%__MODULE__{query: {:module, module}}) do
    sections = [fetch_module_doc(module)]

    fun_sections =
      fetch_functions(module)
      |> Enum.map(fn {_name, _arity, sig, doc_text} ->
        "## #{sig}\n\n#{doc_text}"
      end)

    Enum.join(sections ++ fun_sections, "\n__SECTION__\n")
  end

  def to_sections(%__MODULE__{query: query}) do
    fetch_function_doc(query)
  end

  ############################################################
  #                        Phlow Views                       #
  ############################################################

  @spec doc_view(t(), GtBridge.Phlow.Builder) :: Text.t()
  defview doc_view(%__MODULE__{query: {:module, module}}, builder) do
    builder.text()
    |> Text.title("Module Doc")
    |> Text.priority(10)
    |> Text.string(fetch_module_doc(module))
    |> Text.markdown()
  end

  defview doc_view(%__MODULE__{query: {:type, _, _, _} = query}, builder) do
    builder.text()
    |> Text.title("Type Doc")
    |> Text.priority(10)
    |> Text.string(fetch_type_doc(query))
    |> Text.markdown()
  end

  defview doc_view(%__MODULE__{query: query}, builder) do
    builder.text()
    |> Text.title("Function Doc")
    |> Text.priority(10)
    |> Text.string(fetch_function_doc(query))
    |> Text.markdown()
  end

  @spec functions_view(t(), GtBridge.Phlow.Builder) ::
          ColumnedList.t() | GtBridge.Phlow.Empty.t()
  defview functions_view(
            %__MODULE__{query: {:module, module}},
            builder
          ) do
    funs = fetch_functions(module)

    builder.columned_list()
    |> ColumnedList.title("Functions")
    |> ColumnedList.priority(11)
    |> ColumnedList.items(funs)
    |> ColumnedList.column("Name/Arity", fn {name, arity, _, _} ->
      "#{name}/#{arity}"
    end)
    |> ColumnedList.column("Signature", fn {_, _, sig, _} -> sig end)
    |> ColumnedList.column("Summary", fn {_, _, _, doc} ->
      extract_first_line(doc)
    end)
    |> ColumnedList.send(fn {name, arity, _, _} ->
      %__MODULE__{query: {:function, module, name, arity}}
    end)
  end

  @spec functions_view(t(), GtBridge.Phlow.Builder) ::
          GtBridge.Phlow.Empty.t()
  def functions_view(_self, builder), do: builder.empty()

  @spec types_view(t(), GtBridge.Phlow.Builder) ::
          ColumnedList.t() | GtBridge.Phlow.Empty.t()
  defview types_view(
            %__MODULE__{query: {:module, module}},
            builder
          ) do
    types = fetch_types(module)

    builder.columned_list()
    |> ColumnedList.title("Types")
    |> ColumnedList.priority(12)
    |> ColumnedList.items(types)
    |> ColumnedList.column("Name/Arity", fn {name, arity, _, _} ->
      "#{name}/#{arity}"
    end)
    |> ColumnedList.column("Signature", fn {_, _, sig, _} -> sig end)
    |> ColumnedList.column("Summary", fn {_, _, _, doc} ->
      extract_first_line(doc)
    end)
    |> ColumnedList.send(fn {name, arity, _, _} ->
      %__MODULE__{query: {:type, module, name, arity}}
    end)
  end

  @spec types_view(t(), GtBridge.Phlow.Builder) ::
          GtBridge.Phlow.Empty.t()
  def types_view(_self, builder), do: builder.empty()

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  @spec fetch_module_doc(module()) :: String.t()
  defp fetch_module_doc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} ->
        "# #{inspect(module)}\n\n#{normalize_markdown(doc)}"

      {:docs_v1, _, _, _, :none, _, _} ->
        "# #{inspect(module)}\n\nNo module documentation available."

      _ ->
        "# #{inspect(module)}\n\nDocumentation not available."
    end
  end

  @spec fetch_functions(module()) ::
          list({atom(), non_neg_integer(), String.t(), String.t()})
  defp fetch_functions(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        for {{kind, name, arity}, _, signatures, doc_map, _} <- docs,
            kind in [:function, :macro] do
          sig = List.first(signatures) || "#{name}/#{arity}"
          doc_text = extract_doc_text(doc_map)
          {name, arity, sig, doc_text}
        end

      _ ->
        []
    end
  end

  @spec fetch_types(module()) ::
          list({atom(), non_neg_integer(), String.t(), String.t()})
  defp fetch_types(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        for {{:type, name, arity}, _, signatures, doc_map, _} <- docs do
          sig = List.first(signatures) || "#{name}/#{arity}"
          doc_text = extract_doc_text(doc_map)
          {name, arity, sig, doc_text}
        end

      _ ->
        []
    end
  end

  @spec fetch_type_doc(type_query()) :: String.t()
  defp fetch_type_doc({:type, module, name, arity}) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        matching =
          for {{:type, n, ar}, _, signatures, doc_map, _} <- docs,
              n == name,
              ar == arity do
            sig = List.first(signatures) || "#{n}/#{ar}"
            doc_text = extract_doc_text(doc_map)
            "## #{sig}\n\n#{doc_text}"
          end

        case matching do
          [] ->
            "No documentation found for " <>
              "#{inspect(module)}.#{name}/#{arity}"

          sections ->
            Enum.join(sections, "\n__SECTION__\n")
        end

      _ ->
        "Documentation not available for #{inspect(module)}."
    end
  end

  @spec fetch_function_doc(function_query() | function_arity_query()) ::
          String.t()
  defp fetch_function_doc({:function, module, function}) do
    fetch_matching_docs(module, function, fn _ar -> true end)
  end

  defp fetch_function_doc({:function, module, function, arity}) do
    fetch_matching_docs(module, function, fn ar -> ar == arity end)
  end

  @spec fetch_matching_docs(
          module(),
          atom(),
          (non_neg_integer() -> boolean())
        ) :: String.t()
  defp fetch_matching_docs(module, function, arity_match?) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        matching =
          for {{kind, name, ar}, _, signatures, doc_map, _} <- docs,
              kind in [:function, :macro],
              name == function,
              arity_match?.(ar) do
            sig = List.first(signatures) || "#{name}/#{ar}"
            doc_text = extract_doc_text(doc_map)
            "## #{sig}\n\n#{doc_text}"
          end

        case matching do
          [] ->
            "No documentation found for " <>
              "#{inspect(module)}.#{function}"

          sections ->
            Enum.join(sections, "\n__SECTION__\n")
        end

      _ ->
        "Documentation not available for #{inspect(module)}."
    end
  end

  @spec extract_doc_text(map() | atom()) :: String.t()
  defp extract_doc_text(%{"en" => doc}), do: normalize_markdown(doc)
  defp extract_doc_text(:none), do: "No documentation available."
  defp extract_doc_text(:hidden), do: "(hidden)"
  defp extract_doc_text(_), do: "No documentation available."

  @spec extract_first_line(String.t()) :: String.t()
  defp extract_first_line(text) do
    text
    |> String.split("\n", parts: 2)
    |> List.first("")
    |> String.trim()
  end

  # Convert 4-space indented code blocks to fenced code blocks
  # so LeParser renders them monospaced.
  @spec normalize_markdown(String.t()) :: String.t()
  defp normalize_markdown(text) do
    text
    |> String.split("\n")
    |> fence_code_blocks([])
    |> Enum.join("\n")
  end

  @spec fence_code_blocks(list(String.t()), list(String.t())) ::
          list(String.t())
  defp fence_code_blocks([], acc), do: Enum.reverse(acc)

  defp fence_code_blocks(["```" <> _ = line | rest], acc) do
    {block, remaining} = pass_fenced_block(rest, [line])
    fence_code_blocks(remaining, Enum.reverse(block) ++ acc)
  end

  defp fence_code_blocks(["    " <> _ = line | rest], acc) do
    {block, remaining} = take_code_block([line | rest], [])
    dedented = Enum.map(block, &dedent_code_line/1)
    fence = ["```elixir"] ++ dedented ++ ["```"]
    fence_code_blocks(remaining, Enum.reverse(fence) ++ acc)
  end

  defp fence_code_blocks([line | rest], acc) do
    fence_code_blocks(rest, [line | acc])
  end

  @spec pass_fenced_block(list(String.t()), list(String.t())) ::
          {list(String.t()), list(String.t())}
  defp pass_fenced_block([], acc), do: {Enum.reverse(acc), []}

  defp pass_fenced_block(["```" <> _ = line | rest], acc) do
    {Enum.reverse([line | acc]), rest}
  end

  defp pass_fenced_block([line | rest], acc) do
    pass_fenced_block(rest, [line | acc])
  end

  @spec take_code_block(list(String.t()), list(String.t())) ::
          {list(String.t()), list(String.t())}
  defp take_code_block([], acc), do: {Enum.reverse(acc), []}

  defp take_code_block(["    " <> _ = line | rest], acc) do
    take_code_block(rest, [line | acc])
  end

  defp take_code_block(["" | rest], acc) do
    case rest do
      ["    " <> _ | _] -> take_code_block(rest, ["" | acc])
      _ -> {Enum.reverse(acc), ["" | rest]}
    end
  end

  defp take_code_block(remaining, acc), do: {Enum.reverse(acc), remaining}

  @spec dedent_code_line(String.t()) :: String.t()
  defp dedent_code_line("    " <> rest), do: rest
  defp dedent_code_line(line), do: line
end
