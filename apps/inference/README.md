# Inference

<p align="center">
  <img src="assets/inference.svg" alt="Inference" width="200" />
</p>

<p align="center">
  <a href="https://opensource.org/licenses/MIT">
    <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-0f172a?style=for-the-badge" />
  </a>
  <a href="https://github.com/nshkrdotcom/inference">
    <img alt="GitHub" src="https://img.shields.io/badge/github-nshkrdotcom%2Finference-111827?style=for-the-badge&logo=github" />
  </a>
</p>

`inference` provides reusable Elixir contracts for semantic model inference:
requests, responses, clients, adapters, capabilities, trace metadata,
redaction, and adapter conformance tests.

It is intentionally small. The package gives application code one stable shape
for prompts, responses, client configuration, trace summaries, and adapter
contracts. Provider SDKs, local agent runtimes, governed execution systems, and
transport stacks remain outside the core contract.

It is not an Execution Plane wrapper. Execution Plane remains the lower runtime
substrate. `inference` is the product-facing provider/model boundary used by
standalone libraries such as `trinity_coordinator` and `gepa_ex`.

## Installation

Add `:inference` to the application that wants the shared contract:

```elixir
def deps do
  [
    {:inference, "~> 0.1"}
  ]
end
```

Provider-specific dependencies are opt-in. For example:

```elixir
def deps do
  [
    {:inference, "~> 0.1"},
    {:gemini, "..."},
    {:agent_session_manager, "..."}
  ]
end
```

The initial package ships adapter modules, not separate adapter packages:

- `Inference.Adapters.Mock`
- `Inference.Adapters.ASM`
- `Inference.Adapters.GeminiEx`
- `Inference.Adapters.ReqLlmNext`
- `Inference.Adapters.ReqLLM`

Provider-specific dependencies are opt-in dependencies in the consuming
application. For example, Gemini users add both `:inference` and `:gemini_ex`;
core/mock users add only `:inference`.

Jido governed execution is owned by `jido_integration`. The Jido-owned adapter
implements `Inference.Adapter` from that repository and translates shared
requests into governed control-plane execution.

That governed lane is required release scope for platforms that use universal
auth authority. It remains outside the core `:inference` package so direct
standalone adapters stay reusable, while governed deployments carry authority
refs, credential handles or leases, target grants, and redacted trace evidence
through the Jido-owned adapter.

## Usage

```elixir
client =
  Inference.Client.new!(
    adapter: Inference.Adapters.Mock,
    provider: :mock,
    model: "mock-fast",
    adapter_opts: [response_text: "hello"]
  )

{:ok, response} = Inference.complete(client, "Say hello")
Inference.Response.text(response)
```

Requests can also be built explicitly:

```elixir
{:ok, request} =
  Inference.Request.from_messages([
    %{role: :system, content: "Be concise."},
    %{role: :user, content: "Summarize the result."}
  ])

{:ok, response} = Inference.complete(client, request)
```

## Design Rules

- The default test path is deterministic and mock-only.
- Live provider calls are examples, not test requirements.
- Provider dependencies are installed by the consuming application.
- Adapter modules translate to and from provider libraries; they do not hide
  provider setup, credentials, or runtime requirements.
- `Inference.Adapters.ASM` is common-only. It validates options through ASM
  strict preflight, rejects provider-native tool/configuration keys, and does
  not expose ASM host tools until ASM has a proven all-provider tool contract.
- Jido governed execution is owned by `jido_integration`, which implements
  `Inference.Adapter` from the Jido side.
- Direct `:inference` adapters are standalone mechanics. They do not decide
  durable provider credential authority, target attachment, or workflow
  admission for governed execution.

## Guides

- [Architecture](architecture.html)
- [Requests and Responses](requests-and-responses.html)
- [Clients and Adapters](clients-and-adapters.html)
- [Optional Providers](optional-providers.html)
- [Adapter Testkit](adapter-testkit.html)
- [Live Examples](live-examples.html)
- [Jido Integration Ownership](jido-integration.html)
