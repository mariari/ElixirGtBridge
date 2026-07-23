defmodule GtBridge.Completion do
  @moduledoc """
  I provide code completion for Elixir source fragments.

  Given a code prefix string (everything from the last separator to
  the cursor), I call `Code.Fragment.cursor_context/1` to understand
  what the user is typing and return matching completions from the
  runtime.

  ### Public API

  - `complete/1` — complete with no bindings
  - `complete/2` — complete with bindings from an Eval session
  - `complete/3` — complete with bindings and full source context

  Module names come from `GtBridge.Analysis.LoadedModules`, which is
  maintained by module events and also sees modules an application
  declares but has not yet loaded.
  """

  alias GtBridge.Analysis.LoadedModules

  @doc """
  I return a list of completion strings for `code_prefix`,
  including variable names from `bindings`.

  The optional third argument `source` is the full source text up to
  the cursor. When provided, it is passed through to sub-completers
  that may need surrounding context (e.g. struct field completion).
  """
  @spec complete(String.t(), Code.binding(), String.t() | nil, Macro.Env.t()) ::
          [String.t()]
  def complete(code_prefix, bindings \\ [], source \\ nil, env \\ %Macro.Env{}) do
    aliases = env.aliases

    case Code.Fragment.cursor_context(code_prefix) do
      {:alias, hint} ->
        complete_alias(List.to_string(hint), aliases)

      {:dot, {:alias, mod}, hint} ->
        complete_dot(resolve_alias(mod, aliases), List.to_string(hint), List.to_string(mod))

      {:dot, {:unquoted_atom, mod}, hint} ->
        complete_erlang_dot(List.to_atom(mod), List.to_string(hint))

      {:unquoted_atom, hint} ->
        complete_erlang_module(List.to_string(hint))

      {:local_or_var, hint} ->
        complete_local_or_var(source, List.to_string(hint), bindings, aliases, env)

      {:struct, hint} ->
        complete_struct(struct_prefix(hint))

      :expr ->
        complete_local_or_var(source, "", bindings, aliases, env)

      _ ->
        []
    end
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  defp complete_alias(hint, aliases) do
    depth = length(String.split(hint, "."))

    loaded =
      for short <- LoadedModules.names_with_prefix(hint),
          not String.starts_with?(short, ":") do
        short |> String.split(".") |> Enum.take(depth) |> Enum.join(".")
      end

    aliased =
      for {short, _full} <- aliases,
          name = short |> Atom.to_string() |> String.replace_prefix("Elixir.", ""),
          String.starts_with?(name, hint) do
        name
      end

    (loaded ++ aliased)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp complete_dot(module, hint, display_name) do
    prefix = display_name <> "."
    sigs = function_signatures(module)

    funs =
      try do
        module.__info__(:functions) ++ module.__info__(:macros)
      rescue
        _ -> []
      end

    fun_completions =
      for {fun, arity} <- funs,
          name = Atom.to_string(fun),
          String.starts_with?(name, hint),
          not String.starts_with?(name, "__") do
        sig = Map.get(sigs, {fun, arity})

        suffix =
          if sig,
            do: "/" <> Integer.to_string(arity) <> "(" <> sig <> ")",
            else: "/" <> Integer.to_string(arity)

        prefix <> name <> suffix
      end

    parent = inspect(module) <> "."

    submodule_completions =
      for full <- LoadedModules.names_with_prefix(parent),
          rest = String.replace_prefix(full, parent, ""),
          segment = rest |> String.split(".") |> hd(),
          String.starts_with?(segment, hint) do
        prefix <> segment
      end

    (fun_completions ++ submodule_completions)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp complete_erlang_dot(module, hint) do
    prefix = ":" <> Atom.to_string(module) <> "."

    exports =
      try do
        module.module_info(:exports)
      rescue
        _ -> []
      end

    for {fun, arity} <- exports,
        name = Atom.to_string(fun),
        String.starts_with?(name, hint),
        name != "module_info" do
      prefix <> name <> "/" <> Integer.to_string(arity)
    end
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp complete_erlang_module(hint) do
    # Erlang modules are stored as `inspect/1` renders them, so ":inet"
    # and ~s(:"OTP-PUB-KEY") need separate walks.
    (LoadedModules.names_with_prefix(":" <> hint) ++
       LoadedModules.names_with_prefix(~s(:") <> hint))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp complete_local_or_var(source, hint, bindings, aliases, env) do
    struct_fields = struct_fields_for(source, hint)

    if struct_fields != [] do
      struct_fields
    else
      vars =
        for {name, _val} <- bindings,
            str = Atom.to_string(name),
            String.starts_with?(str, hint) do
          str
        end

      kernel_funs =
        for {fun, arity} <-
              Kernel.__info__(:functions) ++
                Kernel.__info__(:macros),
            name = Atom.to_string(fun),
            String.starts_with?(name, hint),
            not String.starts_with?(name, "__") do
          name <> "/" <> Integer.to_string(arity)
        end

      imported_funs =
        for {mod, funs} <- env.functions ++ env.macros,
            mod != Kernel,
            {fun, arity} <- funs,
            name = Atom.to_string(fun),
            String.starts_with?(name, hint),
            not String.starts_with?(name, "__") do
          name <> "/" <> Integer.to_string(arity)
        end

      root_modules = complete_alias(hint, aliases)

      (vars ++ kernel_funs ++ imported_funs ++ root_modules)
      |> Enum.uniq()
      |> Enum.sort()
    end
  end

  defp struct_fields_for(nil, _hint), do: []

  defp struct_fields_for(source, hint) do
    if inside_open_brace?(source), do: parse_struct_fields(source, hint), else: []
  end

  # A cursor inside `%Struct{...}` needs an unclosed `{`, so counting
  # rules out the parse (~0.14us/byte) cheaply.  Braces in strings count
  # too, so `%User{a: "}"` loses its field completion.
  defp inside_open_brace?(source) do
    length(:binary.matches(source, "{")) > length(:binary.matches(source, "}"))
  end

  defp parse_struct_fields(source, hint) do
    with {:ok, ast} <- Code.Fragment.container_cursor_to_quoted(source),
         {:%, _, [{:__aliases__, _, aliases}, {:%{}, _, _}]} <-
           find_struct_around_cursor(ast),
         module = Module.concat(aliases),
         {:module, _} <- Code.ensure_loaded(module),
         true <- function_exported?(module, :__struct__, 1) do
      for key <- Map.keys(module.__struct__()),
          key != :__struct__,
          name = Atom.to_string(key),
          String.starts_with?(name, hint) do
        name
      end
      |> Enum.sort()
    else
      _ -> []
    end
  end

  defp find_struct_around_cursor({:%, _, [_aliases, {:%{}, _, fields}]} = node) do
    if has_cursor?(fields), do: node, else: nil
  end

  defp find_struct_around_cursor({_, _, children}) when is_list(children) do
    Enum.find_value(children, &find_struct_around_cursor/1)
  end

  defp find_struct_around_cursor([_ | _] = list) do
    Enum.find_value(list, &find_struct_around_cursor/1)
  end

  defp find_struct_around_cursor({left, right}) do
    find_struct_around_cursor(left) || find_struct_around_cursor(right)
  end

  defp find_struct_around_cursor(_), do: nil

  defp has_cursor?({:__cursor__, _, _}), do: true

  defp has_cursor?({_, _, children}) when is_list(children) do
    Enum.any?(children, &has_cursor?/1)
  end

  defp has_cursor?([_ | _] = list), do: Enum.any?(list, &has_cursor?/1)
  defp has_cursor?({left, right}), do: has_cursor?(left) or has_cursor?(right)
  defp has_cursor?(_), do: false

  # 0-arity Kernel special forms (__MODULE__, __ENV__, ...) can stand where a
  # struct name goes, e.g. %__MODULE__{}. Offer them from the language itself
  # rather than naming any one.
  @special_forms for {name, 0} <- Kernel.SpecialForms.__info__(:macros),
                     do: Atom.to_string(name)

  # cursor_context wraps the struct name in the same context tuples it uses
  # elsewhere: a charlist alias (%MapS), a dotted alias (%File.), or a
  # local_or_var for a special form like %__MODULE__. Flatten each to the
  # prefix string complete_struct/1 matches on; anything else has no struct
  # name to complete.
  @spec struct_prefix(charlist() | tuple()) :: String.t() | nil
  defp struct_prefix(hint) when is_list(hint), do: List.to_string(hint)

  defp struct_prefix({:dot, {:alias, mod}, hint}),
    do: List.to_string(mod) <> "." <> List.to_string(hint)

  defp struct_prefix({:local_or_var, hint}), do: List.to_string(hint)
  defp struct_prefix(_), do: nil

  defp complete_struct(nil), do: []

  defp complete_struct(prefix) do
    specials =
      if prefix == "",
        do: [],
        else: for(form <- @special_forms, String.starts_with?(form, prefix), do: "%" <> form)

    modules =
      for {module, _} <- :code.all_loaded(),
          name = Atom.to_string(module),
          String.starts_with?(name, "Elixir."),
          short = String.replace_prefix(name, "Elixir.", ""),
          String.starts_with?(short, prefix),
          function_exported?(module, :__struct__, 1) do
        "%" <> short
      end

    (specials ++ modules) |> Enum.sort()
  end

  defp resolve_alias(charlist, aliases) do
    module = Module.concat([List.to_string(charlist)])
    Keyword.get(aliases, module, module)
  end

  # `Code.fetch_docs/1` reads the whole .beam through
  # `:code.get_object_code/1`; seeking to the one chunk is 2.7x cheaper
  # (851us -> 319us for Enum) and this runs on every dot keystroke.
  defp docs_chunk(module) do
    with path when is_list(path) <- :code.which(module),
         {:ok, {_, [{_, raw}]}} <- :beam_lib.chunks(path, [~c"Docs"]) do
      :erlang.binary_to_term(raw)
    else
      _ -> :error
    end
  end

  defp function_signatures(module) do
    case docs_chunk(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        for {{kind, name, arity}, _, signatures, _, _} <- docs,
            kind in [:function, :macro],
            sig <- signatures,
            into: %{} do
          # signatures are like "map(enumerable, fun)" — strip name prefix
          params = String.replace_prefix(sig, Atom.to_string(name), "")
          params = String.trim_leading(params, "(") |> String.trim_trailing(")")
          {{name, arity}, params}
        end

      _ ->
        %{}
    end
  end
end
