# Architecture

`inference` is the semantic boundary between product code and model-provider
execution.

It owns:

- request and message data structures;
- normalized response data structures;
- client configuration;
- adapter behaviour;
- stable error categories;
- trace summaries;
- metadata redaction;
- adapter conformance helpers.

It does not own:

- provider credentials;
- provider SDK initialization;
- local CLI process lifecycle;
- durable run records;
- policy, routing, leasing, replay, or review packets;
- Execution Plane runtime mechanics.

## Layering

The expected standalone stack is:

```text
application code
  -> Inference.Client
  -> Inference.Adapter implementation
  -> provider SDK or local runtime
```

For governed deployments, Jido Integration implements the adapter from its own
repository:

```text
application code
  -> Inference.Client
  -> Jido-owned Inference.Adapter implementation
  -> Jido Integration inference runtime
  -> provider/runtime family
```

That keeps `:inference` reusable without making it depend on governance
subsystems.

## Package Shape

The repository is an umbrella-style workspace so the package can live at
`apps/inference` while the repository root stays useful for docs, examples, and
future apps.

The initial Hex package is only `:inference`. Adapter modules live inside that
package. Separate adapter packages are deferred until dependency pressure proves
they are worth the extra publishing and versioning overhead.
