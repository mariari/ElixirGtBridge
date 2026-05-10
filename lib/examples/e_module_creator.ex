defmodule Examples.EModuleCreator do
  @moduledoc """
  I am examples for `GtBridge.ModuleCreator`.

  `create_module/0` is the building block: it primes a clean state,
  creates the scratch module, asserts the success payload, and
  returns it — leaving the artifact on disk so downstream examples
  compose on top.  `refuses_existing/0` chains on `create_module/0`
  to reach the "module already exists" precondition without its
  own setup helper, then cleans up after asserting the refusal.

  `rerun?/1` is `true` everywhere because each example has real
  side effects (file write, module load) that caching the result
  would mask.  Composition still works: a chained call re-runs the
  upstream example, which is what we want — the artifact has to
  actually exist on disk for the refusal to fire.
  """

  use ExExample
  import ExUnit.Assertions

  alias GtBridge.ModuleCreator

  def rerun?(_), do: true

  @scratch_module Examples.EModuleCreatorScratch
  @scratch_path "lib/examples/e_module_creator_scratch.ex"

  @spec create_module() :: map()
  example create_module do
    cleanup()
    result = ModuleCreator.create(@scratch_module)

    assert result.path == @scratch_path
    assert File.exists?(result.path)
    assert Code.ensure_loaded?(@scratch_module)

    result
  end

  @spec refuses_existing() :: {:error, :exists}
  example refuses_existing do
    create_module()
    refusal = ModuleCreator.create(@scratch_module)
    assert refusal == {:error, :exists}

    cleanup()
    refusal
  end

  @spec refuses_erlang_atom() :: {:error, :not_elixir_module}
  example refuses_erlang_atom do
    result = ModuleCreator.create(:gen_server)
    assert result == {:error, :not_elixir_module}
    result
  end

  ############################################################
  #                         Helpers                          #
  ############################################################

  # I remove any leftover scratch file.  Used as cleanup-on-entry
  # by `create_module/0` (so re-runs start clean) and as cleanup-
  # on-exit by `refuses_existing/0` (which leaves no artifact since
  # it composes on `create_module/0`'s output and is the terminal
  # link in the chain).
  defp cleanup, do: File.rm(@scratch_path)
end
