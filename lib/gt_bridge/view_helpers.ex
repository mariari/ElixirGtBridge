defmodule GtBridge.ViewHelpers do
  @moduledoc """
  I provide helper functions for views that are written within GT.
  """

  @doc """
  I determine if a given pid is a supervisor.
  """
  @spec determine_supervisor(GenServer.name()) :: boolean()
  def determine_supervisor(name) do
    case :sys.get_state(name) do
      %DynamicSupervisor{} ->
        true

      # Internally it's called :state
      {:state, _, _strategy, _children, _, _, _, _, _, _, _, _} ->
        true

      _ ->
        false
    end
  end
end
