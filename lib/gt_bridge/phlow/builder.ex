defmodule GtBridge.Phlow.Builder do
  @moduledoc """
  Builder for creating Phlow views.

  This module provides factory methods for creating different types of views
  that can be used in defview declarations.
  """

  @doc """
  Create a new text editor view.
  """
  @spec text() :: GtBridge.Phlow.Text.t()
  def text do
    %GtBridge.Phlow.Text{}
  end

  @doc """
  Create a new list view.
  """
  @spec list() :: GtBridge.Phlow.List.t()
  def list do
    %GtBridge.Phlow.List{}
  end
end
