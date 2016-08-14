defmodule HedwigFlowdock.Mixfile do
  use Mix.Project

  @version "0.1.2"

  def project do
    [
      app: :hedwig_flowdock,
      name: "Hedwig Flowdock",
      version: @version,
      elixir: "~> 1.2",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      package: package,
      description: "A Flowdock adapter for Hedwig",
      deps: deps
    ]
  end

  def application do
    [applications: [:logger, :connection, :gun, :hedwig, :poison]]
  end

  defp deps do
    [
      {:connection, "~> 1.0"},
      {:gun, "1.0.0-pre.1"},
      {:hedwig, github: "hedwig-im/hedwig"},
      {:poison, "~> 2.0"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Sean Williamson"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/supernullset/hedwig_flowdock"
      }
    ]
  end
end
