# AGENTS.md

This file defines the working contract for `/home/home/p/g/n/inference`.

## Purpose

`inference` owns the stable shared Elixir contract for model inference:
requests, responses, clients, adapter behaviour, trace summaries, redaction,
and adapter conformance helpers.

It does not own provider credentials, provider SDK setup, durable run records,
governed route selection, leases, replay, review packets, or Execution Plane
runtime mechanics.

## Adapter Boundary Rules

- Preserve `Inference.Client.defaults` unless an adapter explicitly rejects a
  field.
- Preserve `Inference.Request.options` only when the option is part of that
  adapter's contract.
- Request-level options override client defaults.
- Adapter-internal compatibility options, such as raw prompt overrides, must
  not leak into provider or runtime option bags unless documented.
- Propagate provider-reported usage, cost, finish reason, object output, and
  tool-call fields when available. Do not invent provider values.
- Default tests use fake provider modules. Live provider checks belong in
  explicitly gated examples or smoke suites.

## Jido Integration Boundary

Do not add Jido governance logic to this package. `jido_integration` owns the
Jido-owned `Inference.Adapter` implementation that translates shared
`Inference.Client` / `Inference.Request` calls into governed control-plane
execution and durable run truth.

When changing shared semantics that the Jido adapter depends on, run this
package gate and then run `mix ci` in `/home/home/p/g/n/jido_integration`.

## Validation

Run from `/home/home/p/g/n/inference/apps/inference`:

```bash
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --strict
mix dialyzer
mix docs
```

