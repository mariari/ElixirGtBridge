defmodule Examples.ECompletion.Wrapped do
  @moduledoc false

  # Deliberately the brace-group form, wide enough to stay wrapped:
  # this fixture guards multi-line directive parsing. Don't "fix" the
  # style - one-alias-per-line would never wrap and the coverage dies.
  alias GtBridge.Analysis.{
    Source,
    Walker,
    CallSites,
    Graph,
    LoadedModules,
    Interfaces
  }

  import Enum,
    only: [map: 2]

  @doc false
  def touch, do: {Source, Walker, CallSites, Graph, LoadedModules, Interfaces, map([], & &1)}
end

defmodule Examples.ECompletion do
  @moduledoc """
  I am examples for the Elixir autocompletion system.
  """

  use ExExample

  import ExUnit.Assertions

  alias GtBridge.Completion

  @spec complete_enum_dot() :: [String.t()]
  example complete_enum_dot do
    results = Completion.complete("Enum.ma")

    assert Enum.any?(results, &String.starts_with?(&1, "Enum.map/2"))
    assert Enum.any?(results, &String.starts_with?(&1, "Enum.map_every/3"))

    results
  end

  @spec complete_alias() :: [String.t()]
  example complete_alias do
    results = Completion.complete("GenSer")

    assert "GenServer" in results

    results
  end

  @spec complete_erlang_module() :: [String.t()]
  example complete_erlang_module do
    results = Completion.complete(":erlan")

    assert ":erlang" in results

    results
  end

  @spec complete_erlang_dot() :: [String.t()]
  example complete_erlang_dot do
    results = Completion.complete(":erlang.no")

    assert ":erlang.node/0" in results

    results
  end

  @spec complete_with_bindings() :: [String.t()]
  example complete_with_bindings do
    results = Completion.complete("my_v", my_var: 42, my_val: "hello")

    assert "my_var" in results
    assert "my_val" in results

    results
  end

  @spec complete_struct() :: [String.t()]
  example complete_struct do
    results = Completion.complete("%MapS")

    assert "%MapSet" in results

    results
  end

  @spec complete_struct_non_alias() :: [String.t()]
  example complete_struct_non_alias do
    # cursor_context wraps these struct names in nested context tuples, not a
    # plain charlist. We still complete the ones we know: the %__MODULE__
    # special form and structs under a dotted alias (%File. -> %File.Stat).
    assert Completion.complete("%__MOD") == ["%__MODULE__"]
    assert "%File.Stat" in Completion.complete("%File.")

    # Shapes with no known struct name complete to nothing (and never crash).
    assert Completion.complete("%@foo") == []
    assert Completion.complete("%foo.bar") == []

    Completion.complete("%__MOD")
  end

  @spec complete_struct_fields() :: [String.t()]
  example complete_struct_fields do
    # GT sends "ho" as code (from { separator) and full source for context
    results = Completion.complete("ho", [], "%URI{ho")

    assert "host" in results
    assert "port" not in results

    # Without source context, falls back to normal local_or_var
    fallback = Completion.complete("ho")
    assert "host" not in fallback

    results
  end

  @spec complete_kernel_with_arity() :: [String.t()]
  example complete_kernel_with_arity do
    results = Completion.complete("is_")

    assert "is_atom/1" in results
    assert length(results) > 0

    results
  end

  @spec complete_module_locals() :: [String.t()]
  example complete_module_locals do
    # An editor session primed on a module completes its publics
    # (via import) and its defps (injected by the preamble).
    sid = GtBridge.Eval.Preamble.editor_session(Completion, "e_completion_locals")
    results = GtBridge.Eval.complete(GtBridge.EvalRegistry.get_or_create(sid), "complete")

    assert Enum.any?(results, &String.starts_with?(&1, "complete/"))
    assert Enum.any?(results, &String.starts_with?(&1, "complete_local_or_var/"))

    results
  end

  @spec preamble_directives_parse_alone() :: [String.t()]
  example preamble_directives_parse_alone do
    # GT prepends these verbatim to inspector snippet evals; the old
    # line scan handed over fragments of wrapped directives, killing
    # the whole snippet with a syntax error the user never wrote. The
    # fixture alias group is wide enough that the formatter keeps it
    # wrapped, so this also pins the one-line render (Macro.to_string
    # reproduces source line breaks unless told otherwise).
    lines = GtBridge.Eval.Preamble.directives(Examples.ECompletion.Wrapped)

    assert length(lines) == 2
    assert Enum.all?(lines, &match?({:ok, _}, Code.string_to_quoted(&1)))
    assert Enum.any?(lines, &String.contains?(&1, "LoadedModules"))

    lines
  end
end
