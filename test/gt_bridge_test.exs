defmodule GtBridgeTest do
  use ExUnit.Case
  doctest GtBridge
end

defmodule GtBridgeTest.Tcp do
  use ExExample.ExUnit, for: Examples.ETcp
end

defmodule GtBridgeTest.Serialization do
  use ExExample.ExUnit, for: Examples.ESerialization
end

defmodule GtBridgeTest.Eval do
  use ExExample.ExUnit, for: Examples.EEval
end

defmodule GtBridgeTest.Completion do
  use ExExample.ExUnit, for: Examples.ECompletion
end

defmodule GtBridgeTest.Mondrian do
  use ExExample.ExUnit, for: Examples.EMondrian
end

defmodule GtBridgeTest.Views do
  use ExExample.ExUnit, for: Examples.EViews
end

defmodule GtBridgeTest.Documentation do
  use ExExample.ExUnit, for: Examples.EDocumentation
end

defmodule GtBridgeTest.Analysis do
  use ExUnit.Case

  test "implementors/2 entries include all keys expected by Smalltalk side" do
    required = [:name, :arity, :module, :kind, :start, :end_line, :sig, :source]
    results = GtBridge.Analysis.implementors(:new, nil)

    assert length(results) > 0

    for entry <- results, key <- required do
      assert Map.has_key?(entry, key), "missing #{inspect(key)} in #{inspect(entry)}"
    end
  end
end

defmodule GtBridgeTest.CodeMonitor do
  use ExExample.ExUnit, for: Examples.ECodeMonitor
end
