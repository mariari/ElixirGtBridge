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

  @doc """
  Create a new columned list view.
  """
  @spec columned_list() :: GtBridge.Phlow.ColumnedList.t()
  def columned_list do
    %GtBridge.Phlow.ColumnedList{}
  end

  @doc """
  Create a new columned tree view.
  """
  @spec columned_tree() :: GtBridge.Phlow.ColumnedTree.t()
  def columned_tree do
    %GtBridge.Phlow.ColumnedTree{}
  end

  @doc """
  Create a new empty view.
  """
  @spec empty() :: GtBridge.Phlow.Empty.t()
  def empty do
    %GtBridge.Phlow.Empty{}
  end
end
