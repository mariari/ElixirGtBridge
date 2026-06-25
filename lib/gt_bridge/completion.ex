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
  """

  @doc """
  I return a list of completion strings for `code_prefix`.
  """
  @spec complete(String.t()) :: [String.t()]
  def complete(code_prefix), do: complete(code_prefix, [])

  @doc """
  I return a list of completion strings for `code_prefix`,
  including variable names from `bindings`.
  """
  @spec complete(String.t(), Code.binding()) :: [String.t()]
  def complete(code_prefix, bindings) do
    case Code.Fragment.cursor_context(code_prefix) do
      {:alias, hint} ->
        complete_alias(List.to_string(hint))

      {:dot, {:alias, mod}, hint} ->
        complete_dot(resolve_alias(mod), List.to_string(hint))

      {:dot, {:unquoted_atom, mod}, hint} ->
        complete_erlang_dot(List.to_atom(mod), List.to_string(hint))

      {:unquoted_atom, hint} ->
        complete_erlang_module(List.to_string(hint))

      {:local_or_var, hint} ->
        complete_local_or_var(List.to_string(hint), bindings)

      {:struct, hint} ->
        complete_struct(struct_prefix(hint))

      :expr ->
        complete_local_or_var("", bindings)

      _ ->
        []
    end
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  defp complete_alias(hint) do
    for {module, _} <- :code.all_loaded(),
        name = Atom.to_string(module),
        String.starts_with?(name, "Elixir."),
        short = String.replace_prefix(name, "Elixir.", ""),
        not String.contains?(short, "."),
        String.starts_with?(short, hint) do
      short
    end
    |> Enum.sort()
  end

  defp complete_dot(module, hint) do
    prefix = inspect(module) <> "."

    funs =
      try do
        module.__info__(:functions) ++ module.__info__(:macros)
      rescue
        _ -> []
      end

    for {fun, _arity} <- funs,
        name = Atom.to_string(fun),
        String.starts_with?(name, hint),
        not String.starts_with?(name, "__") do
      prefix <> name
    end
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

    for {fun, _arity} <- exports,
        name = Atom.to_string(fun),
        String.starts_with?(name, hint),
        name != "module_info" do
      prefix <> name
    end
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp complete_erlang_module(hint) do
    for {module, _} <- :code.all_loaded(),
        name = Atom.to_string(module),
        not String.starts_with?(name, "Elixir."),
        String.starts_with?(name, hint) do
      ":" <> name
    end
    |> Enum.sort()
  end

  defp complete_local_or_var(hint, bindings) do
    vars =
      for {name, _val} <- bindings,
          str = Atom.to_string(name),
          String.starts_with?(str, hint) do
        str
      end

    kernel_funs =
      for {fun, _arity} <-
            Kernel.__info__(:functions) ++
              Kernel.__info__(:macros),
          name = Atom.to_string(fun),
          String.starts_with?(name, hint),
          not String.starts_with?(name, "__") do
        name
      end

    root_modules = complete_alias(hint)

    (vars ++ kernel_funs ++ root_modules)
    |> Enum.uniq()
    |> Enum.sort()
  end

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

  defp resolve_alias(charlist) do
    Module.concat([List.to_string(charlist)])
  end
end
