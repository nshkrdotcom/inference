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

## Response format

`:response_format` is a closed union, normalized and validated when the request
is built:

- `nil` — unspecified;
- `:text` — plain assistant text;
- `{:json, :object}` — schemaless JSON object mode;
- `{:json_schema, %{name: name, schema: schema, strict: strict?}}` — a named
  schema (`:strict` defaults to `true`).

```elixir
{:ok, request} =
  Inference.Request.from_prompt("Extract the fields.",
    response_format:
      {:json_schema,
       %{name: "route", schema: %{"type" => "object"}}}
  )
```

Anything outside the union is an `:invalid` error with reason
`:response_format`, before any provider call. Every adapter either maps a
declared format onto a real provider option — ASM's `:output_schema`, Gemini's
`responseJsonSchema`/`responseMimeType`, ReqLLM's `generate_object/4` — or
returns `{:error, %Inference.Error{reason: :response_format_unsupported}}`.
Adapters never drop a declared format silently.

Ask before dispatching with `Inference.capabilities/1`:

```elixir
capabilities = Inference.capabilities(client)
Inference.Capability.supported?(capabilities, :response_format_json_schema)
```

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
- usage, cost, and finish reason;
- raw provider result for in-memory use;
- metadata and trace summary.

Do not persist raw provider responses by default. Persist redacted trace and
summary fields instead.

`cost` is provider-reported only. Adapters should copy cost data when the
underlying provider returns it, but they must not invent cost values for
providers that do not expose them.
