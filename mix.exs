defmodule GtBridge.MixProject do
  use Mix.Project

  def project do
    [
      app: :gt_bridge,
      version: "0.7.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      plt_add_apps: [:mix, :ex_unit],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {GtBridge, []},
      extra_applications: [:logger, :observer, :wx, :ex_unit, :iex]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:msgpax, "~> 2.4"},
      {:typed_struct, "~> 0.3.0"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:plug_cowboy, "~> 2.7.3"},
      # We need faithful encoding and decoding of atoms
      {:jexon, "~> 0.9.5"},
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:req, "~> 0.5.0"}
    ]
  end
end
