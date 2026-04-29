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

It is not an Execution Plane wrapper. Execution Plane remains the lower runtime
substrate. `inference` is the product-facing provider/model boundary used by
standalone libraries such as `trinity_coordinator` and `gepa_ex`.

The initial package ships adapter modules, not separate adapter packages:

- `Inference.Adapters.Mock`
- `Inference.Adapters.ASM`
- `Inference.Adapters.GeminiEx`
- `Inference.Adapters.ReqLlmNext`
- `Inference.Adapters.ReqLLM`

Provider-specific dependencies are opt-in dependencies in the consuming
application. For example, Gemini users add both `:inference` and `:gemini_ex`;
core/mock users add only `:inference`.

Jido governed execution is future work owned by `jido_integration`, where a
Jido-owned module can implement `Inference.Adapter`.

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

Live provider examples are documented in `guides/live_examples.md` and in the
repository-level `examples/README.md`.
