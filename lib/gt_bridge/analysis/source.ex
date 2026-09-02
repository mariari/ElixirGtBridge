defmodule GtBridge.Analysis.Source do
  @moduledoc """
  I am the pure source-text half of Analysis: function/type entry
  extraction (strict and lenient), module scoping for multi-module
  files, and the canonical source-edit splices (swap/replace/append).
  I never touch the code server; beam-side merging stays in
  `GtBridge.Analysis`.
  """

  # One home for the parse options every source walk uses.
  @quoted_opts [columns: true, token_metadata: true]

  @doc "I parse `source` with the options every source walk uses."
  @spec quoted(String.t()) :: {:ok, Macro.t()} | {:error, term()}
  def quoted(source), do: Code.string_to_quoted(source, @quoted_opts)

  @doc """
  I extract the top-level `defmodule X.Y` name from `source`. Returns
  the dotted module string, or nil when the source doesn't define one
  or doesn't parse.
  """
  @spec module_in_source(String.t()) :: String.t() | nil
  def module_in_source(source) do
    case modules_in_source(source) do
      [first | _] ->
        first

      [] ->
        # Parse failed (syntax error elsewhere).  The defmodule line
        # itself almost always parses; pull the name by regex so error
        # notifications still name the right module.
        module_in_source_lenient(source)
    end
  end

  defp module_in_source_lenient(source) do
    case Regex.run(~r/^\s*defmodule\s+([A-Z][A-Za-z0-9_.]*)\b/m, source) do
      [_, name] -> name
      _ -> nil
    end
  end

  @doc """
  I return every module `source` defines (nested `defmodule`s and
  `typedstruct module:` children included) as dotted-name strings.
  Returns `[]` when the source doesn't parse.
  """
  @spec modules_in_source(String.t()) :: [String.t()]
  def modules_in_source(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} -> Enum.map(module_nodes(ast, ""), &elem(&1, 0))
      _ -> []
    end
  end

  @doc """
  I parse `source` and return the AST function entries (the same shape
  `all_functions/1` returns minus the runtime-export merging, which
  needs the module to be loaded). Works on disk bytes alone, so safe
  to call before / after a failed compile.
  """
  @spec functions_in_source(String.t()) :: [map()]
  def functions_in_source(source) do
    case quoted(source) do
      {:ok, ast} ->
        lines = String.split(source, "\n")
        stmts = outer_statements(ast)
        functions_from_statements(stmts, lines) ++ types_from_statements(stmts, lines)

      _ ->
        lenient_function_entries(source)
    end
  end

  @doc """
  I return the alias/import/require statements `ast` declares — whole
  statements, so formatter-wrapped directives arrive intact. With no
  module I sweep the top level and every top-level module (buffer
  semantics); given a dotted module name I scope to that module's own
  body, so siblings in the same file don't leak theirs in.
  """
  @spec directives(Macro.t(), String.t() | nil) :: [Macro.t()]
  def directives(ast, module \\ nil)

  def directives(ast, nil) do
    ast
    |> body_statements()
    |> Enum.flat_map(fn
      {:defmodule, _, [_, [do: body]]} -> body_statements(body)
      stmt -> [stmt]
    end)
    |> Enum.filter(&directive?/1)
  end

  def directives(ast, module) do
    case module_scope(ast, module) do
      {:defmodule, _, [_, [do: body]]} -> body |> body_statements() |> Enum.filter(&directive?/1)
      _ -> []
    end
  end

  defp directive?(stmt),
    do: match?({kind, _, [_ | _]} when kind in [:alias, :import, :require], stmt)

  @doc """
  I swap two functions (by `{name, arity}`) within `module` in `source`,
  taking ranges from `source` itself so the splice can't drift. Unknown
  name/arity returns `source` unchanged.
  """
  @spec swap_functions(String.t(), String.t(), String.t(), arity(), String.t(), arity()) ::
          String.t()
  def swap_functions(source, module, name_a, arity_a, name_b, arity_b) do
    entries = module_source_entries(source, module)

    with a when not is_nil(a) <- find_function(entries, name_a, arity_a),
         b when not is_nil(b) <- find_function(entries, name_b, arity_b) do
      rewrite(source, [{a, text_lines(b.source)}, {b, text_lines(a.source)}])
    else
      _ -> source
    end
  end

  @doc """
  I replace the `{name, arity}` function within `module` in `source` with
  `new_text` (or remove it when `new_text` is empty), taking the range from
  `source` itself so the splice can't drift. Unknown name/arity returns
  `source` unchanged.
  """
  @spec replace_function(String.t(), String.t(), String.t(), arity(), String.t()) :: String.t()
  def replace_function(source, module, name, arity, new_text) do
    case find_function(module_source_entries(source, module), name, arity) do
      nil -> source
      f -> rewrite(source, [{f, text_lines(new_text)}])
    end
  end

  @doc """
  I append `new_text` as a new function just before `module`'s closing `end`,
  located from the parse so a sibling or nested module in the same file doesn't
  misdirect it. Returns `source` unchanged when `module` has no `defmodule` to
  append to (e.g. a typedstruct-generated module), or the source doesn't parse.
  """
  @spec append_function(String.t(), String.t(), String.t()) :: String.t()
  def append_function(source, module, new_text) do
    with {:ok, ast} <- Code.string_to_quoted(source, token_metadata: true),
         {:defmodule, meta, _} <- module_scope(ast, module),
         line when is_integer(line) <- get_in(meta, [:end, :line]) do
      # a zero-width edit at `line` inserts the blank + new function before end
      rewrite(source, [{%{start: line, end_line: line - 1}, ["" | text_lines(new_text)]}])
    else
      _ -> source
    end
  end

  # Replace disjoint function ranges: each {entry, lines} swaps
  # entry.start..entry.end_line for lines. Spliced in source order so the
  # untouched line numbers stay valid as we go.
  defp rewrite(source, edits) do
    lines = String.split(source, "\n")

    {out, last} =
      edits
      |> Enum.sort_by(fn {e, _} -> e.start end)
      |> Enum.flat_map_reduce(0, fn {e, repl}, cursor ->
        {take_lines(lines, cursor + 1, e.start - 1) ++ repl, e.end_line}
      end)

    (out ++ take_lines(lines, last + 1, length(lines))) |> Enum.join("\n")
  end

  defp text_lines(""), do: []
  defp text_lines(text), do: String.split(text, "\n")

  defp find_function(entries, name, arity),
    do: Enum.find(entries, &(&1.name == name and &1.arity == arity))

  # 1-indexed inclusive slice; the from > to guard matters because
  # (from - 1)..(to - 1) wraps to the whole list when to is 0.
  defp take_lines(_lines, from, to) when from > to, do: []
  defp take_lines(lines, from, to), do: Enum.slice(lines, (from - 1)..(to - 1))
  # Per-fn fallback for files where whole-module AST parse fails (stray
  # `end`, mid-edit).  For each def header, find the smallest end_line
  # whose slice wrapped in `defmodule __X__ do ... end` parses to a
  # single def AST.  Headers that don't balance within @lenient_max_fn_lines
  # are skipped; the compile-error popup names the file to fix.
  @lenient_max_fn_lines 200
  @lenient_def_header ~r/^\s*(def|defp|defmacro|defmacrop|defview|example)\s+\w/
  defp lenient_function_entries(source) do
    lines = String.split(source, "\n")
    total = length(lines)
    do_lenient(lines, 1, total, []) |> Enum.reverse() |> merge_clauses()
  end

  defp do_lenient(_lines, line_num, total, acc) when line_num > total, do: acc

  defp do_lenient(lines, line_num, total, acc) do
    line = Enum.at(lines, line_num - 1, "")

    if Regex.match?(@lenient_def_header, line) do
      case extract_lenient_at(lines, line_num, total) do
        {:ok, entry} -> do_lenient(lines, entry.end_line + 1, total, [entry | acc])
        :error -> do_lenient(lines, line_num + 1, total, acc)
      end
    else
      do_lenient(lines, line_num + 1, total, acc)
    end
  end

  defp extract_lenient_at(lines, start_line, total) do
    max_end = min(start_line + @lenient_max_fn_lines - 1, total)

    Enum.reduce_while(start_line..max_end, :error, fn end_line, _acc ->
      body = slice_lines(lines, start_line, end_line)
      wrapped = "defmodule __GtBridgeLenient__ do\n" <> body <> "\nend\n"

      case Code.string_to_quoted(wrapped) do
        {:ok, ast} ->
          case lenient_fn_info(ast) do
            {:ok, name, arity, kind_str} ->
              walked_start = walk_back_annotations(lines, start_line)

              full_slice = slice_lines(lines, walked_start, end_line)

              entry = %{
                name: Atom.to_string(name),
                arity: arity,
                kind: kind_str,
                sig: "#{name}/#{arity}",
                start: walked_start,
                end_line: end_line,
                source: full_slice,
                defaults: 0
              }

              {:halt, {:ok, entry}}

            :error ->
              {:cont, :error}
          end

        _ ->
          {:cont, :error}
      end
    end)
  end

  # Atoms that look like function definers (def, defp, defmacro, defmacrop,
  # plus user macros like defview) but aren't function-defining themselves.
  @non_function_def_kinds [
    :defmodule,
    :defstruct,
    :defguard,
    :defguardp,
    :defprotocol,
    :defimpl,
    :defdelegate,
    :deftype,
    :defrecord,
    :defrecordp,
    :defexception,
    :defoverridable
  ]
  # User-level macros that expand to function definitions and
  # whose AST source we want captured so the inspector shows the
  # body. Without this allowlist they fall through to the runtime
  # export path and render as "(no source)".
  @function_def_macros [:example]
  defp lenient_fn_info({:defmodule, _, [_, [do: {kind, _, [head | _]}]]}) when is_atom(kind) do
    kind_str = Atom.to_string(kind)

    cond do
      kind in @non_function_def_kinds -> :error
      kind in @function_def_macros -> head_to_info(head, "def")
      String.starts_with?(kind_str, "def") -> head_to_info(head, kind_str)
      true -> :error
    end
  end

  defp lenient_fn_info(_), do: :error

  defp head_to_info(head, kind_str) do
    case function_head(head) do
      {name, arity} -> {:ok, name, arity, kind_str}
      _ -> :error
    end
  end

  defp type_row(name, arity, kind, start, end_line, lines) do
    %{
      name: name,
      arity: arity,
      kind: kind,
      start: start,
      end_line: end_line,
      sig: "#{name}/#{arity}",
      source: slice_lines(lines, start, end_line)
    }
  end

  # typedstruct carries its block as the `:do` of the last arg, whether
  # written `typedstruct do`, `typedstruct enforce: true do`, or
  # `typedstruct(opts) do` — match on that, not a bare `[[do: _]]`.
  defp typedstruct_do?(args) do
    kw = List.last(args)
    is_list(kw) and Keyword.keyword?(kw) and Keyword.has_key?(kw, :do)
  end

  # Function/type entries for one module, scoped to its own subtree so a nested
  # or sibling module in the same file doesn't leak the other's. `module` is the
  # dotted name string. Shared by all_functions/1 and the edit ops.
  @spec module_source_entries(String.t(), String.t()) :: [map()]
  def module_source_entries(source, module) do
    case quoted(source) do
      {:ok, ast} ->
        lines = String.split(source, "\n")

        case module_scope(ast, module) do
          {:defmodule, _, [_, [do: body]]} ->
            stmts = body_statements(body)
            functions_from_statements(stmts, lines) ++ types_from_statements(stmts, lines)

          {:typedstruct, _, _} = node ->
            typedstruct_type(node, lines)

          nil ->
            []
        end

      _ ->
        lenient_function_entries(source)
    end
  end

  # The one traversal that knows what counts as a module: nested
  # defmodules and `typedstruct module: X` children, as {dotted_name, node}
  # pairs. Name listing and scope lookup are projections of it; both the
  # read and write paths resolve "which module is this" here.
  @spec module_nodes(Macro.t(), String.t()) :: [{String.t(), Macro.t()}]
  defp module_nodes({:__block__, _, stmts}, prefix),
    do: Enum.flat_map(stmts, &module_nodes(&1, prefix))

  defp module_nodes({:defmodule, _, [{:__aliases__, _, parts}, [do: body]]} = node, prefix) do
    full = qualify(prefix, Enum.map_join(parts, ".", &Atom.to_string/1))
    [{full, node} | module_nodes(body, full)]
  end

  defp module_nodes({:typedstruct, _, _} = node, prefix) do
    case typedstruct_submodule(node) do
      nil -> []
      sub -> [{qualify(prefix, sub), node}]
    end
  end

  defp module_nodes(_, _), do: []

  @spec module_scope(Macro.t(), String.t()) :: Macro.t() | nil
  defp module_scope(ast, target),
    do: Enum.find_value(module_nodes(ast, ""), fn {name, node} -> name == target && node end)

  @spec qualify(String.t(), String.t()) :: String.t()
  defp qualify("", suffix), do: suffix
  defp qualify(prefix, suffix), do: prefix <> "." <> suffix
  @spec body_statements(Macro.t()) :: [Macro.t()]
  defp body_statements({:__block__, _, stmts}), do: stmts
  defp body_statements(single), do: [single]
  # A typedstruct's `module:` option as a dotted string, or nil for a plain
  # typedstruct (whose `t` belongs to the enclosing module). The option can be
  # in any leading keyword arg, so scan them all.
  @spec typedstruct_submodule(Macro.t()) :: String.t() | nil
  defp typedstruct_submodule({:typedstruct, _, args}) when is_list(args) do
    module =
      args
      |> Enum.filter(&(is_list(&1) and Keyword.keyword?(&1)))
      |> Enum.find_value(&Keyword.get(&1, :module))

    case module do
      {:__aliases__, _, parts} -> Enum.map_join(parts, ".", &Atom.to_string/1)
      _ -> nil
    end
  end

  defp typedstruct_submodule(_), do: nil
  @spec functions_from_statements([Macro.t()], [String.t()]) :: [map()]
  defp functions_from_statements(stmts, lines) do
    ann = annotation_starts(stmts)

    stmts
    |> Enum.flat_map(&function_entry/1)
    |> merge_clauses()
    |> Enum.map(fn f ->
      start = extend_over_comments(lines, Map.get(ann, f.start, f.start))
      %{f | start: start} |> Map.put(:source, slice_lines(lines, start, f.end_line))
    end)
  end

  # First line of the @doc/@spec/@impl run above each statement, keyed by the
  # statement's line: an attribute spans lines freely where a line walk trips.
  @annotation_attrs [:doc, :spec, :impl]
  @spec annotation_starts([Macro.t()]) :: %{pos_integer() => pos_integer()}
  defp annotation_starts(stmts) do
    stmts
    |> Enum.reduce({%{}, nil}, fn
      {:@, meta, [{attr, _, _}]}, {map, run} when attr in @annotation_attrs ->
        {map, run || meta[:line]}

      {_, meta, _}, {map, run} when run != nil and is_list(meta) ->
        {Map.put(map, meta[:line], run), nil}

      _, {map, _} ->
        {map, nil}
    end)
    |> elem(0)
  end

  @spec extend_over_comments([String.t()], pos_integer()) :: pos_integer()
  defp extend_over_comments(lines, start) when start > 1 do
    if String.starts_with?(String.trim(Enum.at(lines, start - 2, "")), "#") do
      extend_over_comments(lines, start - 1)
    else
      start
    end
  end

  defp extend_over_comments(_lines, start), do: start

  # @type/@opaque/@typep plus a plain typedstruct's `t`, from direct statements.
  # A `typedstruct module: X` is skipped; its `t` is the child's, not ours.
  # Single source of type rows for both the source-written and recompiled
  # cache primes; typedstruct's `t` wins a name clash (listed first, uniq_by).
  @spec types_from_statements([Macro.t()], [String.t()]) :: [map()]
  defp types_from_statements(stmts, lines) do
    typedstruct =
      Enum.find_value(stmts, [], fn
        {:typedstruct, _, _} = node ->
          if typedstruct_submodule(node) == nil, do: typedstruct_type(node, lines)

        _ ->
          nil
      end)

    decls = Enum.flat_map(stmts, &type_decl(&1, lines))
    (typedstruct ++ decls) |> Enum.uniq_by(&{&1.name, &1.arity})
  end

  @spec typedstruct_type(Macro.t(), [String.t()]) :: [map()]
  defp typedstruct_type({:typedstruct, meta, args}, lines) do
    if typedstruct_do?(args) do
      s = Keyword.get(meta, :line)
      e = get_in(meta, [:end, :line]) || s
      [type_row("t", 0, :type, s, e, lines)]
    else
      []
    end
  end

  @spec type_decl(Macro.t(), [String.t()]) :: [map()]
  defp type_decl({:@, meta, [{kind, _, [{:"::", _, [{name, _, args} | _]}]}]}, lines)
       when kind in [:type, :opaque, :typep] and is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    s = Keyword.get(meta, :line)
    e = get_in(meta, [:end_of_expression, :line]) || s
    [type_row(Atom.to_string(name), arity, kind, s, e, lines)]
  end

  defp type_decl(_, _), do: []
  defp slice_lines(lines, s, e), do: take_lines(lines, s, e) |> Enum.join("\n")

  defp merge_clauses(entries) do
    # Merge consecutive entries with the same name/arity/kind
    # into a single entry spanning all clauses.
    Enum.reduce(Enum.reverse(entries), [], fn entry, acc ->
      case acc do
        [prev | rest]
        when prev.name == entry.name and prev.arity == entry.arity and prev.kind == entry.kind ->
          [%{entry | end_line: prev.end_line} | rest]

        _ ->
          [entry | acc]
      end
    end)
  end

  # No AST to consult here: anchor at the farthest @doc/@spec/@impl line whose
  # slice down to the def parses as pure annotations (heredocs and wrapped
  # specs come out whole), then take adjacent comments like the strict path.
  defp walk_back_annotations(lines, def_start) do
    anchor =
      (def_start - 1)..max(def_start - @lenient_max_fn_lines, 1)//-1
      |> Enum.filter(fn i ->
        String.starts_with?(String.trim(Enum.at(lines, i - 1, "")), ["@doc", "@spec", "@impl"])
      end)
      |> Enum.reverse()
      |> Enum.find(&pure_annotations?(slice_lines(lines, &1, def_start - 1)))

    extend_over_comments(lines, anchor || def_start)
  end

  defp pure_annotations?(slice) do
    case Code.string_to_quoted(slice) do
      {:ok, ast} -> Enum.all?(body_statements(ast), &annotation?/1)
      _ -> false
    end
  end

  defp annotation?({:@, _, [{attr, _, _}]}), do: attr in @annotation_attrs
  defp annotation?(_), do: false

  def source_function_names(source, ast) do
    lines = String.split(source, "\n")

    stmts = outer_statements(ast)

    (Enum.flat_map(stmts, &function_entry/1) ++ types_from_statements(stmts, lines))
    |> Enum.map(& &1.name)
    |> MapSet.new()
  end

  # The outer module's direct statements; anything else has none.
  # A file with a second top-level form parses as a block.
  defp outer_statements({:__block__, _, stmts}), do: Enum.flat_map(stmts, &outer_statements/1)
  defp outer_statements({:defmodule, _, [_, [do: body]]}), do: body_statements(body)
  defp outer_statements(_), do: []

  defp function_entry({kind, meta, [head | _]}) when is_atom(kind) do
    kind_str = Atom.to_string(kind)

    cond do
      kind in @function_def_macros ->
        function_entry_for("def", head, meta)

      not String.starts_with?(kind_str, "def") ->
        []

      kind in @non_function_def_kinds ->
        []

      true ->
        function_entry_for(kind_str, head, meta)
    end
  end

  defp function_entry(_), do: []

  defp function_entry_for(kind_str, head, meta) do
    case function_head(head) do
      {name, arity} when is_atom(name) and is_integer(arity) ->
        function_record(kind_str, name, arity, default_count(head), meta)

      _ ->
        []
    end
  end

  defp function_record(kind_str, name, arity, defaults, meta) do
    end_line = meta[:end][:line] || meta[:end_of_expression][:line] || meta[:line]

    [
      %{
        name: Atom.to_string(name),
        arity: arity,
        kind: kind_str,
        start: meta[:line],
        end_line: end_line,
        sig: "#{name}/#{arity}",
        defaults: defaults
      }
    ]
  end

  # Arities `arity - defaults` .. `arity - 1` are generated heads
  # with no def of their own.
  defp default_count({:when, _, [head | _]}), do: default_count(head)

  defp default_count({_, _, args}) when is_list(args),
    do: Enum.count(args, &match?({:\\, _, _}, &1))

  defp default_count(_), do: 0
  defp function_head({:when, _, [head | _]}), do: function_head(head)

  defp function_head({name, _, args}) when is_atom(name) and is_list(args),
    do: {name, length(args)}

  defp function_head({name, _, _}) when is_atom(name), do: {name, 0}
  defp function_head(name) when is_atom(name), do: {name, 0}
  # Catch-all so non-name heads (e.g. `__aliases__` tuples wrapped
  # by some macro form) fall through to the case clause's `[]`
  # branch instead of raising FunctionClauseError.
  defp function_head(_), do: nil
end
