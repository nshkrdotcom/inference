# Requests And Responses

`Inference.Request` and `Inference.Response` are deliberately plain structs.
They are meant to be easy to inspect, trace, redact, and convert to provider
payloads.

## Requests

Build a request from prompt text:

```elixir
{:ok, request} = Inference.Request.from_prompt("Explain the route.")
```

Build a request from messages:

```elixir
{:ok, request} =
  Inference.Request.from_messages([
    %{role: :system, content: "Be terse."},
    %{role: :user, content: "Explain the route."}
  ])
```

Valid roles are:

- `:system`
- `:user`
- `:assistant`
- `:tool`

Invalid roles and empty content fail before adapter dispatch.

## Responses

Adapters return `Inference.Response`:

```elixir
{:ok, response} = Inference.complete(client, request)
text = Inference.Response.text(response)
```

The response carries:

- provider and model identifiers;
- normalized text;
- optional object output and tool calls;
- usage and finish reason;
- raw provider result for in-memory use;
- metadata and trace summary.

Do not persist raw provider responses by default. Persist redacted trace and
summary fields instead.
