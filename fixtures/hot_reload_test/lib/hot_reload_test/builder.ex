defmodule HotReloadTest.Builder do
  @moduledoc "I create Config structs. I am a struct caller. Changing
  config's fields should propagate to me via ParallelCompiler."

  alias HotReloadTest.Config

  def new_config, do: %Config{}

  def new_config(name, value), do: %Config{name: name, value: value}

  def default_value, do: %Config{}.value
end
