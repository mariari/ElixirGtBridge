defmodule Examples.EDocumentation do
  @moduledoc """
  I am examples for GtBridge.Documentation, the module doc extractor.
  """

  use ExExample

  import ExUnit.Assertions

  alias GtBridge.Documentation

  def rerun?(_), do: true

  ############################################################
  #                  Module-Level Examples                   #
  ############################################################

  @spec for_enum() :: Documentation.t()
  example for_enum do
    doc = Documentation.for_module(Enum)

    assert doc.query == {:module, Enum}

    doc
  end

  @spec module_doc_view() :: map()
  example module_doc_view do
    doc = for_enum()
    views = GtBridge.View.get_view_object(doc)

    md_view = Enum.find(views, &(&1[:title] == "Module Doc"))
    assert md_view != nil
    assert md_view[:markdown] == true
    assert is_binary(md_view[:string])
    assert String.contains?(md_view[:string], "Enum")

    md_view
  end

  @spec functions_view() :: map()
  example functions_view do
    doc = for_enum()
    views = GtBridge.View.get_view_object(doc)

    funs_view = Enum.find(views, &(&1[:title] == "Functions"))
    assert funs_view != nil
    assert funs_view[:itemsCount] > 0

    funs_view
  end

  @spec no_docs_module() :: map()
  example no_docs_module do
    doc = Documentation.for_module(NoDocsTestModule)
    views = GtBridge.View.get_view_object(doc)

    md_view = Enum.find(views, &(&1[:title] == "Module Doc"))
    assert md_view != nil
    assert String.contains?(md_view[:string], "not available")

    md_view
  end

  ############################################################
  #                 Function-Level Examples                  #
  ############################################################

  @spec for_enum_map() :: Documentation.t()
  example for_enum_map do
    doc = Documentation.for_function(Enum, :map)

    assert doc.query == {:function, Enum, :map}

    doc
  end

  @spec for_enum_map_2() :: Documentation.t()
  example for_enum_map_2 do
    doc = Documentation.for_function(Enum, :map, 2)

    assert doc.query == {:function, Enum, :map, 2}

    doc
  end

  @spec function_doc_view() :: map()
  example function_doc_view do
    doc = for_enum_map_2()
    views = GtBridge.View.get_view_object(doc)

    md_view = Enum.find(views, &(&1[:title] == "Function Doc"))
    assert md_view != nil
    assert String.contains?(md_view[:string], "map")

    md_view
  end

  @spec multi_arity_sections() :: map()
  example multi_arity_sections do
    doc = Documentation.for_function(Enum, :reduce)
    views = GtBridge.View.get_view_object(doc)

    md_view = Enum.find(views, &(&1[:title] == "Function Doc"))
    assert md_view != nil
    # reduce/2 and reduce/3 should be separate sections
    assert String.contains?(md_view[:string], "__SECTION__")

    md_view
  end

  ############################################################
  #                   Type-Level Examples                    #
  ############################################################

  @spec types_view() :: map()
  example types_view do
    doc = for_enum()
    views = GtBridge.View.get_view_object(doc)

    types_view = Enum.find(views, &(&1[:title] == "Types"))
    assert types_view != nil
    assert types_view[:itemsCount] > 0

    types_view
  end

  @spec type_doc_view() :: map()
  example type_doc_view do
    doc = Documentation.for_type(Enum, :t, 0)
    views = GtBridge.View.get_view_object(doc)

    md_view = Enum.find(views, &(&1[:title] == "Type Doc"))
    assert md_view != nil

    md_view
  end

  ############################################################
  #                    Sections Example                      #
  ############################################################

  @spec to_sections() :: String.t()
  example to_sections do
    doc = for_enum()
    sections = Documentation.to_sections(doc)

    assert is_binary(sections)
    assert String.contains?(sections, "__SECTION__")

    parts = String.split(sections, "\n__SECTION__\n")
    # First section is the module doc
    assert String.starts_with?(hd(parts), "# Enum")
    # Subsequent sections have ## headers
    assert Enum.all?(tl(parts), &String.starts_with?(&1, "## "))
    # Indented code blocks are converted to fenced
    assert String.contains?(sections, "```elixir")
    refute String.contains?(sections, "    iex>")

    sections
  end
end
