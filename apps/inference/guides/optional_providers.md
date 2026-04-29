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
{:gemini_ex, "..."}
```

Configure credentials in the SDK, then use `Inference.Adapters.GeminiEx`.

## Agent Session Manager

Install Agent Session Manager in the consuming app:

```elixir
{:inference, "~> 0.1"},
{:agent_session_manager, "..."}
```

Use `Inference.Adapters.ASM` with a provider atom or session reference.

The adapter supports normal query calls and managed streaming sessions when the
installed ASM module exposes `query/3`, `start_session/1`, `stream/3`, and
`stop_session/1`. String sessions are passed to ASM as `:session_id` while the
provider atom remains the query target; pid sessions are treated as external
sessions.

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

```elixir
{:inference, "~> 0.1"},
{:req_llm, "~> 1.10"}
```

The compatibility adapter supports text generation, structured object
generation through `generate_object/4`, provider key aliasing for OpenAI,
Gemini, and Anthropic, and portable tool structs that expose `:name`,
`:description`, `:input_schema`, and `:run`.

## Missing Dependencies

If an adapter is selected but its underlying provider module is unavailable, the
adapter returns `Inference.Error` with category `:missing_dependency`.
