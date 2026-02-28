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
  """

  @doc """
  I return a list of completion strings for `code_prefix`,
  including variable names from `bindings`.

  The optional third argument `source` is the full source text up to
  the cursor. When provided, it is passed through to sub-completers
  that may need surrounding context (e.g. struct field completion).
  """
  @spec complete(String.t(), Code.binding(), String.t() | nil) :: [String.t()]
  def complete(code_prefix, bindings \\ [], source \\ nil) do
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
        complete_local_or_var(source, List.to_string(hint), bindings)

      {:struct, hint} ->
        complete_struct(List.to_string(hint))

      :expr ->
        complete_local_or_var(source, "", bindings)

      _ ->
        []
    end
  end

  ############################################################
  #                   Private Implementation                 #
  ############################################################

  defp complete_alias(hint) do
    depth = length(String.split(hint, "."))

    for {module, _} <- :code.all_loaded(),
        name = Atom.to_string(module),
        String.starts_with?(name, "Elixir."),
        short = String.replace_prefix(name, "Elixir.", ""),
        String.starts_with?(short, hint) do
      short |> String.split(".") |> Enum.take(depth) |> Enum.join(".")
    end
    |> Enum.uniq()
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

    fun_completions =
      for {fun, _arity} <- funs,
          name = Atom.to_string(fun),
          String.starts_with?(name, hint),
          not String.starts_with?(name, "__") do
        prefix <> name
      end

    parent = Atom.to_string(module) <> "."

    submodule_completions =
      for {mod, _} <- :code.all_loaded(),
          full = Atom.to_string(mod),
          String.starts_with?(full, parent),
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

  defp complete_local_or_var(_source, hint, bindings) do
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

  defp complete_struct(hint) do
    for {module, _} <- :code.all_loaded(),
        name = Atom.to_string(module),
        String.starts_with?(name, "Elixir."),
        short = String.replace_prefix(name, "Elixir.", ""),
        String.starts_with?(short, hint),
        function_exported?(module, :__struct__, 1) do
      short
    end
    |> Enum.sort()
  end

  defp resolve_alias(charlist) do
    Module.concat([List.to_string(charlist)])
  end
end
