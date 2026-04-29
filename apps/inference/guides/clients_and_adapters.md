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
