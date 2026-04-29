# Optional Providers

Optional provider support means the consuming app opts into provider
dependencies. It does not mean this repository publishes a package per adapter.

## Mock

No extra dependency is required:

```elixir
{:inference, "~> 0.1"}
```

## GeminiEx

Install the Gemini SDK in the consuming app:

```elixir
{:inference, "~> 0.1"},
{:gemini, "..."}
```

Configure credentials in the SDK, then use `Inference.Adapters.GeminiEx`.

## Agent Session Manager

Install Agent Session Manager in the consuming app:

```elixir
{:inference, "~> 0.1"},
{:agent_session_manager, "..."}
```

Use `Inference.Adapters.ASM` with a provider atom or session reference.

## ReqLlmNext

Install ReqLlmNext where broad hosted-provider coverage is needed:

```elixir
{:inference, "~> 0.1"},
{:req_llm_next, "..."}
```

Use `Inference.Adapters.ReqLlmNext`.

## ReqLLM Compatibility

`Inference.Adapters.ReqLLM` is for compatibility with existing users. Prefer
ReqLlmNext for new broad hosted-provider work.

## Missing Dependencies

If an adapter is selected but its underlying provider module is unavailable, the
adapter returns `Inference.Error` with category `:missing_dependency`.
