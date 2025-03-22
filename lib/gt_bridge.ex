defmodule GtBridge do
  use Application

  @moduledoc """
  Documentation for `GtBridge`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> GtBridge.hello()
      :world

  """
  def hello do
    :world
  end

  def start(_type, args) do
    GtBridge.Supervisor.start_link(args)
  end
end
