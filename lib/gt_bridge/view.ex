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

  ############################################################
  #               Helpers For Determining Module             #
  ############################################################

  @spec match_view_argument_to_module(Macro.t(), Macro.Env.t()) :: module()
  def match_view_argument_to_module(args, env) do
    x = GtBridge.View.match_view_argument(args, env)

    if is_nil(x) do
      quote do
        __MODULE__
      end
    else
      x
    end
  end

  @doc """
  I handle matching arguments to resolve the module for `defview/1`.

  Most data structures will resolve however there are a few exceptions:

  1. 3 tuples, are not supported as it overlaps with `Macro.t/0`.
  2. Atoms are not supports, as it overlaps with `x = y`
  """
  @spec match_view_argument(Macro.t(), Macro.Env.t()) :: module() | nil
  def match_view_argument([{:\\, _, [arg_l, _]} | args], caller) do
    match_view_argument([arg_l, args], caller)
  end

  def match_view_argument([{:=, _, [arg_l, arg_r]} | args], caller) do
    match_view_argument([determine_constraining_arg(arg_l, arg_r), args], caller)
  end

  def match_view_argument([arg | _args], caller) do
    match_arg(arg, caller)
  end

  # TODO Make this more robust
  @spec determine_constraining_arg(Macro.t(), Macro.t()) :: Macro.t()
  def determine_constraining_arg({atom, _, _}, arg2) when is_atom(atom) do
    arg2
  end

  def determine_constraining_arg(arg1, _), do: arg1

  @spec match_arg(Macro.t(), Macro.Env.t()) :: module() | nil
  def match_arg({:%, _, [{:__aliases__, _, atoms} | _]}, caller) do
    case Macro.Env.expand_alias(caller, [], atoms) do
      {:alias, module} -> module
      :error -> atoms |> Enum.reverse() |> Enum.reduce(&Module.concat/2)
    end
  end

  def match_arg({:%, _, [{:__MODULE__, _, _} | _]}, _), do: nil
  def match_arg({:%{}, _, keyword}, _), do: Keyword.get(keyword, :__struct__, Map)

  def match_arg(x, caller) when is_tuple(x) do
    expanded = Macro.expand(x, caller)

    if x == expanded do
      case x do
        {value, _, _} ->
          match_arg(value, caller)

        # If it's not a 3 tuple likely actually a tuple view
        _ ->
          Tuple
      end
    else
      match_arg(expanded, caller)
    end
  end

  def match_arg(x, _) when is_list(x) do
    List
  end

  def match_arg(x, _) when is_pid(x) do
    Pid
  end

  # Don't handle atom, x = y. Fallback on failure
  def match_arg(x, _) when is_atom(x) do
    nil
  end

  # These types don't get resolved to proxy objects currently

  def match_arg({:<<>>, _, _}, _), do: Binary

  def match_arg(x, _) when is_integer(x) do
    Integer
  end

  def match_arg(x, _) when is_float(x) do
    Float
  end
end
