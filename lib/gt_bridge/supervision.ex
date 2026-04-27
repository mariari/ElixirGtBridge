defmodule GtBridge.Supervision do
  @moduledoc """
  I expose process-supervision introspection to GT.

  My single public function `tree/1` walks a supervisor's children
  recursively and returns a nested map structure suitable for
  Mondrian-tree rendering on the GT side.
  """

  @doc """
  I return a nested supervision tree starting from a PID.

  Each node is a map with `:pid`, `:name`, `:module`, `:supervisor`,
  `:children`, `:queue`, and `:status`. Large worker pools appear
  as-is — GT collapses them during rendering.
  """
  @spec tree(pid()) :: map()
  def tree(pid) when is_pid(pid), do: build_node(pid)

  defp build_node(pid) do
    info =
      Process.info(pid, [
        :dictionary,
        :initial_call,
        :status,
        :message_queue_len,
        :registered_name
      ])

    name =
      case info[:registered_name] do
        [] -> inspect(pid)
        n -> inspect(n)
      end

    mod =
      case info[:dictionary][:"$initial_call"] || info[:initial_call] do
        {m, _, _} -> m
        _ -> nil
      end

    is_sup = mod != nil and function_exported?(mod, :which_children, 1)

    children =
      if is_sup do
        # which_children calls into the supervisor's GenServer, which may
        # exit if it dies between the is_sup check and this call. rescue
        # only catches raises (ArgumentError on a non-supervisor pid);
        # catch :exit handles the dead-process case.
        try do
          for {_, child_pid, _, _} <- Supervisor.which_children(pid),
              is_pid(child_pid),
              Process.alive?(child_pid),
              do: build_node(child_pid)
        rescue
          _ in [ArgumentError] -> []
        catch
          :exit, _ -> []
        end
      else
        []
      end

    %{
      pid: inspect(pid),
      name: name,
      module: inspect(mod),
      supervisor: is_sup,
      children: children,
      queue: info[:message_queue_len] || 0,
      status: to_string(info[:status] || :unknown)
    }
  end
end
