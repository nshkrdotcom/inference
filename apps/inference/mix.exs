defmodule Inference.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :inference,
      version: @version,
      elixir: "~> 1.18",
      description:
        "Reusable semantic inference contracts, adapters, tracing, and conformance tests for Elixir AI systems.",
      source_url: "https://github.com/nshkrdotcom/inference",
      homepage_url: "https://github.com/nshkrdotcom/inference",
      start_permanent: Mix.env() == :prod,
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Inference.Application, []}
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: :inference,
      licenses: ["MIT"],
      maintainers: ["nshkrdotcom"],
      links: %{GitHub: "https://github.com/nshkrdotcom/inference"},
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE", "assets", "guides"]
    ]
  end

  defp docs do
    [
      main: "overview",
      source_ref: "v#{@version}",
      source_url: "https://github.com/nshkrdotcom/inference",
      extras: [
        {"README.md", [filename: "overview", title: "Overview"]},
        "CHANGELOG.md",
        "LICENSE",
        "guides/live_examples.md"
      ],
      groups_for_extras: [
        Project: ~r/^(README|CHANGELOG|LICENSE)/,
        Guides: ~r/^guides\//
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
