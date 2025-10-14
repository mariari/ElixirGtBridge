defmodule GtBridge.View do
  @moduledoc """
  Helper macros for declaring Phlow views on typed structs.

  Use `use GtBridge.View` in your struct module and define views
  using `defview/2`. The collected views can later be registered
  in a `GtBridge.Views` GenServer with `register/2`.

  ## Example

      defmodule MyStruct do
        use TypedStruct
        use GtBridge.View

        typedstruct do
          field(:items, list(), default: [])
        end

        defview list_view(self, builder) do
          builder.list()
          |> GtBridge.Phlow.List.title("Items")
          |> GtBridge.Phlow.List.priority(1)
          |> GtBridge.Phlow.List.items(fn -> self.items end)
        end
      end
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
    module = env.module

    quote do
      @doc false
      def __views__ do
        unquote(Macro.escape(views))
      end

      # Auto-register views when the module is loaded
      @after_compile __MODULE__

      def __after_compile__(_env, _bytecode) do
        # Register this module's views automatically
        try do
          GtBridge.View.register(unquote(module))
        rescue
          # Ignore errors during compilation (e.g., if Views server not started yet)
          _ -> :ok
        end
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

  @doc """
  Get all view specifications for a given object by calling its registered views.
  Returns a list of dictionaries ready for serialization to GT.
  """
  @spec get_view_specs(any(), GenServer.server()) :: list(map())
  def get_view_specs(object, server \\ GtBridge.Views) do
    module = object.__struct__
    views = GtBridge.Views.lookup(server, module)
    builder = GtBridge.Phlow.Builder

    Enum.map(views, fn {mod, fun} ->
      view_result = apply(mod, fun, [object, builder])
      view_module = view_result.__struct__
      apply(view_module, :as_dict, [view_result])
    end)
  end
end
