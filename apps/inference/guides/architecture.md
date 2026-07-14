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

## Provider Kinds

Every adapter reports one closed provider kind:

- `:model_endpoint` for hosted model APIs;
- `:local_model_endpoint` for a future provider-neutral local endpoint;
- `:agent_session` for stateful agent/session runtimes.

Clients admit the two model-endpoint kinds by default. Selecting an ASM agent
session requires explicit `:agent_session` admission, preserving workspace,
continuation, approval, and tool semantics instead of silently presenting the
session as a plain completion endpoint.

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
  -> authority-selected credential and target refs
  -> provider/runtime family
```

That keeps `:inference` reusable without making it depend on governance
subsystems. The standalone stack can use direct adapter credentials and local
runtime setup. The governed stack cannot use those defaults as authority; it
must receive authority refs, credential handles or leases, target grants, and
redacted materialization evidence from the owning control plane.

`Inference.GovernedAuthority` is provider-neutral. It validates and carries the
shared ref envelope that downstream governed adapters need, but it does not
issue leases, select routes, attach targets, or materialize raw provider
secrets. Those remain owned by the control-plane adapter repository.

## Package Shape

The repository is an umbrella-style workspace so the package can live at
`apps/inference` while the repository root stays useful for docs, examples, and
future apps.

The initial Hex package is only `:inference`. Adapter modules live inside that
package. Separate adapter packages are deferred until dependency pressure proves
they are worth the extra publishing and versioning overhead.

`Inference.Adapters.GeminiEx` targets the direct Gemini API. Gemini CLI is
retired; Antigravity is the current Google coding-agent SDK and is available
through the explicitly admitted ASM agent-session family.
