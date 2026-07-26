# Optional Providers

Optional provider support means the consuming app opts into provider
dependencies. It does not mean this repository publishes a package per adapter.

## Mock

No extra dependency is required:

```elixir
{:inference, "~> 0.2.0"}
```

## GeminiEx

Install the direct Gemini API SDK in the consuming app:

```elixir
{:inference, "~> 0.2.0"},
{:gemini_ex, "..."}
```

Configure credentials in the SDK, then use `Inference.Adapters.GeminiEx`.
This is a model endpoint. Gemini CLI is retired and is not a compatibility
route for this adapter.

## Agent Session Manager

Install Agent Session Manager in the consuming app:

```elixir
{:inference, "~> 0.2.0"},
{:agent_session_manager, "..."}
```

Use `Inference.Adapters.ASM` with a provider atom or session reference.

ASM reports `:agent_session`, so clients must set
`admitted_kinds: [:agent_session]`. Antigravity is the current Google
coding-agent SDK behind the ASM family; it is distinct from the direct Gemini
API provided by `GeminiEx`.

The adapter supports normal query calls and managed streaming sessions when the
installed ASM module exposes `query/3`, `start_session/1`, `stream/3`, and
`stop_session/1`. String sessions are passed to ASM as `:session_id` while the
provider atom remains the query target; pid sessions are treated as external
sessions.

The ASM adapter is intentionally common-only and completion-only. ASM owns the
run-path option gate (`ASM.Options.validate/2`), so the adapter does not call
ASM's strict-common preflight from the outside; it maps the neutral request onto
ASM options, locks `completion_only: true`, and rejects tool-bearing requests
until ASM has a documented all-provider host-tool contract.

A `{:json_schema, %{schema: schema}}` response format becomes ASM's
`:output_schema` option (inline JSON for Claude, a materialized schema file for
Codex). Schemaless `{:json, :object}` mode is refused, because ASM structured
output is schema-driven.

`Inference.capabilities/1` answers whether the bound provider does JSON Schema.
The claim is read at runtime from ASM's own feature manifest
(`ASM.ProviderFeatures.common_feature(provider, :structured_output)`); a
provider that declares no such feature — or an application that has not
installed ASM at all — reports `:unknown` rather than assumed support. Tests can
inject a stand-in through the `:asm_provider_features_module` adapter option,
the same way `:asm_module` overrides the runtime module.

## ReqLlmNext

Install ReqLlmNext where broad hosted-provider coverage is needed:

```elixir
{:inference, "~> 0.2.0"},
{:req_llm_next, "..."}
```

Use `Inference.Adapters.ReqLlmNext`.

## ReqLLM Compatibility

`Inference.Adapters.ReqLLM` is for compatibility with existing users. Prefer
ReqLlmNext for new broad hosted-provider work.

```elixir
{:inference, "~> 0.2.0"},
{:req_llm, "~> 1.10"}
```

The compatibility adapter supports text generation, structured object
generation through `generate_object/4`, provider key aliasing for OpenAI,
Gemini, and Anthropic, and portable tool structs that expose `:name`,
`:description`, `:input_schema`, and `:run`.

For standalone clients, the compatibility adapter can still use provider-local
env configured by the consuming application. For governed clients, env fallback
is skipped and direct provider keys are rejected before adapter dispatch.

## Missing Dependencies

If an adapter is selected but its underlying provider module is unavailable, the
adapter returns `Inference.Error` with category `:missing_dependency`.
