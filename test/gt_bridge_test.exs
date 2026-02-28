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
