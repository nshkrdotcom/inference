# Clients And Adapters

`Inference.Client` selects the adapter and carries defaults for a provider call.

```elixir
client =
  Inference.Client.new!(
    adapter: Inference.Adapters.Mock,
    provider: :mock,
    model: "mock-fast",
    defaults: [temperature: 0.2],
    adapter_opts: [response_text: "ok"]
  )
```

Then call through the facade:

```elixir
{:ok, response} = Inference.complete(client, "Hello")
```

## Adapter Behaviour

Adapter modules implement `Inference.Adapter`:

```elixir
@callback complete(Inference.Client.t(), Inference.Request.t()) ::
            {:ok, Inference.Response.t()} | {:error, Inference.Error.t()}

@callback stream(Inference.Client.t(), Inference.Request.t()) ::
            {:ok, Enumerable.t()} | {:error, Inference.Error.t()}
```

`stream/2` is optional at the behaviour level. If an adapter module exposes
`stream/2` but does not support streaming yet, return
`Inference.Error` with category `:unsupported_capability`.

## Adapter Modules

The initial package includes:

- `Inference.Adapters.Mock`
- `Inference.Adapters.ASM`
- `Inference.Adapters.GeminiEx`
- `Inference.Adapters.ReqLlmNext`
- `Inference.Adapters.ReqLLM`

Only the mock adapter is fully self-contained. Other adapters require the
consuming application or live example script to install the underlying provider
dependency.

Adapters may also honor adapter-specific entries in `Inference.Request.options`.
The compatibility adapters currently use this for migration support:

- `Inference.Adapters.ReqLLM` accepts `:prompt` to preserve caller-native prompt
  shape, `:api_key` for per-call credentials, `:tools` for portable tool
  structs, and `:tool_choice` for provider tool-selection controls.
- `Inference.Adapters.ASM` accepts `:prompt` to preserve raw CLI prompt text and
  converts string sessions to ASM `:session_id` options. `:prompt` is internal
  to the inference adapter and is removed before query, session, or stream
  options are passed to Agent Session Manager. The adapter validates the final
  ASM option list through strict ASM preflight and rejects provider-native tool
  keys such as `:tools`, `:tool_choice`, `:host_tools`, and `:dynamic_tools`
  until ASM exposes a proven all-provider tool contract.

These options are intentionally adapter-bound. Core application code should
prefer the stable request fields unless it is implementing a compatibility
wrapper for an existing API.

Adapters should propagate provider usage, cost, finish reason, and tool-call
fields onto `Inference.Response` whenever the underlying runtime reports them.
The shared response helper extracts those fields from map or struct provider
results.

## Contract-Preservation Checklist

Use this checklist before changing a shared adapter boundary:

- `Inference.Client.defaults` are merged into request execution options.
- `Inference.Request.options` are accepted only for adapter-owned semantics.
- Request-level options override client defaults.
- Internal compatibility options are consumed internally or documented as
  forwarded provider options.
- Usage, cost, finish reason, object output, and tool calls are copied when the
  provider/runtime reports them.
- Provider-reported values are never invented by the shared package.
- Adapter tests prove the option precedence and response-field propagation that
  downstream governed adapters depend on.
