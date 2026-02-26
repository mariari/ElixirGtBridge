defmodule GtBridge.MixProject do
  use Mix.Project

  @version "0.10.0"
  @source_url "https://github.com/mariari/ElixirGtBridge"

  def project do
    [
      app: :gt_bridge,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      plt_add_apps: [:mix, :ex_unit],
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {GtBridge, []},
      extra_applications:
        [:logger, :ex_unit, :iex] ++
          if(Mix.env() == :dev, do: [:observer, :wx], else: [])
    ]
  end

  defp description do
    "A bridge between Glamorous Toolkit (GT) and the BEAM VM, enabling remote code evaluation, object inspection, and Phlow view rendering."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end

  defp deps do
    [
      {:msgpax, "~> 2.4"},
      {:typed_struct, "~> 0.3.0"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:plug_cowboy, "~> 2.7.3"},
      # We need faithful encoding and decoding of atoms
      {:jexon, "~> 0.9.5"},
      {:req, "~> 0.5.0"}
    ]
  end
end
