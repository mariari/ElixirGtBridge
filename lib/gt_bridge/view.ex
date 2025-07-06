defmodule GtBridge.View do
  @moduledoc """
  Helper macros for declaring Phlow views on typed structs.

  Use `use GtBridge.View` in your struct module and define views
  using `defview/2`. The collected views can later be registered
  in a `GtBridge.Views` GenServer with `register/2`.
  """

  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :gt_views, accumulate: true)
      import GtBridge.View, only: [defview: 2]
      @before_compile GtBridge.View
    end
  end

  defmacro defview({name, _meta, args}, do: body) do
    quote do
      def unquote(name)(unquote_splicing(args)) do
        unquote(body)
      end

      @gt_views {__MODULE__, unquote(name)}
    end
  end

  defmacro __before_compile__(env) do
    views = Module.get_attribute(env.module, :gt_views) |> Enum.reverse()

    quote do
      @doc false
      def __views__ do
        unquote(Macro.escape(views))
      end
    end
  end

  @doc """
  Register all views defined in `module` into the given `server`.
  """
  @spec register(module(), GenServer.server()) :: :ok
  def register(module, server \\ GtBridge.Views) do
    for {m, fun} <- module.__views__() do
      GtBridge.Views.add(server, module, {m, fun})
    end

    :ok
  end
end
