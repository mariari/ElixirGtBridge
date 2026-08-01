defmodule GtBridge.Beam do
  @moduledoc """
  I read beam-file chunks directly.

  `Code.fetch_docs/1` pulls the whole object code through
  `:code.get_object_code/1`; seeking to the one chunk is ~2.7x
  cheaper (851us -> 319us for Enum), and doc reads happen on every
  dot keystroke and on app-wide coverage sweeps.

  ### Public API

  - `docs/1`
  """

  @doc "I return the `docs_v1` chunk term for `module`, or `:error`."
  @spec docs(module()) :: tuple() | :error
  def docs(module) do
    with path when is_list(path) <- :code.which(module),
         {:ok, {_, [{_, raw}]}} <- :beam_lib.chunks(path, [~c"Docs"]) do
      :erlang.binary_to_term(raw)
    else
      _ -> :error
    end
  end
end
