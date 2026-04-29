# Jido Integration Ownership

Jido governed execution is future work owned by `jido_integration`.

Do not add a Jido adapter to the `:inference` package. `:inference` owns the
semantic contract and adapter behaviour. Jido Integration owns durable run
records, route selection, leases, credential references, replay, review packets,
and platform projections.

The intended dependency direction is:

```text
jido_integration
  -> depends on :inference
  -> implements a Jido-owned module satisfying Inference.Adapter
```

That lets standalone applications use direct adapters while governed
deployments opt into Jido:

```text
application
  -> Inference.Client
  -> Jido-owned Inference.Adapter implementation
  -> Jido Integration inference runtime
```

The Jido-owned adapter should map:

- `Inference.Request` into Jido inference request/command contracts;
- Jido durable result and review ids back into `Inference.Response`;
- Jido route, policy, credential, replay, and review metadata into
  redacted `Inference.Trace` metadata.
