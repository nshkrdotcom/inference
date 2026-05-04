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
      logo: "assets/inference.svg",
      extras: [
        {"README.md", [filename: "overview", title: "Overview"]},
        {"guides/architecture.md", [filename: "architecture", title: "Architecture"]},
        {"guides/requests_and_responses.md",
         [filename: "requests-and-responses", title: "Requests And Responses"]},
        {"guides/clients_and_adapters.md",
         [filename: "clients-and-adapters", title: "Clients And Adapters"]},
        {"guides/optional_providers.md",
         [filename: "optional-providers", title: "Optional Providers"]},
        {"guides/adapter_testkit.md", [filename: "adapter-testkit", title: "Adapter Testkit"]},
        {"guides/live_examples.md", [filename: "live-examples", title: "Live Examples"]},
        {"guides/jido_integration.md",
         [filename: "jido-integration", title: "Jido Integration Ownership"]},
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Overview: ["README.md"],
        Guides: [
          "guides/architecture.md",
          "guides/requests_and_responses.md",
          "guides/clients_and_adapters.md",
          "guides/optional_providers.md",
          "guides/adapter_testkit.md",
          "guides/live_examples.md",
          "guides/jido_integration.md"
        ],
        Project: ["CHANGELOG.md", "LICENSE"]
      ],
      groups_for_modules: [
        Core: [
          Inference,
          Inference.Request,
          Inference.Message,
          Inference.Response,
          Inference.Client,
          Inference.Adapter,
          Inference.GovernedAuthority,
          Inference.Capability,
          Inference.Error,
          Inference.StreamEvent,
          Inference.Trace,
          Inference.Redaction
        ],
        Adapters: [
          Inference.Adapters.Mock,
          Inference.Adapters.ASM,
          Inference.Adapters.GeminiEx,
          Inference.Adapters.ReqLlmNext,
          Inference.Adapters.ReqLLM
        ],
        Testkit: [
          Inference.Testkit.AdapterCase
        ]
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
