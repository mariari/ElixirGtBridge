defmodule GtBridge.ViewHelpers do
  @moduledoc """

  I provide helper functions for views that are written within GT

  """

  @doc """
  I determine if a given pid is a supervisor
  """
  @spec determine_supervisor(GenServer.name()) :: boolean()
  def determine_supervisor(name) do
    case :sys.get_state(name) do
      %DynamicSupervisor{} ->
        true

      # Internally it's called  :state
      {:state, _, _strategy, _children, _, _, _, _, _, _, _, _} ->
        true

      _ ->
        false
    end
  end

  @spec build_supervision(GenServer.name()) :: list({pid(), term(), [pid()]})
  def build_supervision(supervisor) when is_pid(supervisor) do
    iterate_tree([{:root, supervisor, :supervisor, []}])
  end

  def build_supervision(supervisor) do
    build_supervision(Process.whereis(supervisor))
  end

  @spec iterate_tree(list()) :: list({pid(), term(), [pid()]})
  @doc """
  I return a nested list of {pid, name, [pid()]}, which represent the
  children relation
  """
  def iterate_tree(list) do
    list
    |> Enum.flat_map(fn
      {_name, pid, :supervisor, _module} ->
        children = Supervisor.which_children(pid)

        [
          {pid, determine_name(pid), Enum.map(children, fn {_, pid, _, _} -> pid end)}
          | iterate_tree(children)
        ]

      {_name, pid, :worker, _module} ->
        [{pid, determine_name(pid), []}]
    end)
  end

  @spec determine_name(pid()) :: any()
  def determine_name(pid) do
    proc_name =
      case :proc_lib.get_label(pid) do
        :undefined -> pid
        name -> name
      end

    case Process.info(pid, :registered_name) do
      {:registered_name, []} ->
        proc_name

      nil ->
        proc_name

      {:registered_name, name} ->
        name
    end
  end
end
