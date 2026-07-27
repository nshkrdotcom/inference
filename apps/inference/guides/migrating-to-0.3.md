# Migrating To 0.3

Inference `0.3.0` makes the ASM completion-only boundary provider-aware.

## Dependency Update

```elixir
{:inference, "~> 0.3.0"}
```

Applications using `Inference.Adapters.ASM` should pair it with Agent Session
Manager `0.12.0` or later so the adapter can read the total common-feature
manifest:

```elixir
{:agent_session_manager, "~> 0.12.0"}
```

## Provider Behavior

Claude and Codex continue to support text completion, streaming, and
schema-driven structured output through ASM's locked `completion_only: true`
profile.

Amp, Antigravity, and Cursor remain recognized ASM agent-session providers, but
their SDK feature manifests do not currently prove completion-only execution.
Inference now returns `Inference.Error` with category
`:unsupported_capability` before query or stream dispatch for those providers.
It no longer advertises text or streaming support that it cannot prove.

Call `Inference.capabilities/1` before selecting an ASM provider when provider
choice is dynamic. The `:completion_only`, `:response_format_text`,
`:response_format_json_schema`, and `:streaming` claims are manifest-driven.
An older ASM release without the feature catalog reports `:unknown`; runtime
calls still forward the locked completion-only option and leave ASM as the
final gate.

## Dependency Boundary

Inference remains provider-neutral. Do not add Codex, Claude, Amp,
Antigravity, Cursor, or ASM as direct dependencies of the package itself.
Provider dependencies belong in the consuming application.
