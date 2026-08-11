# Migrating To 0.4

Inference 0.4 makes managed Gemini streaming subscription atomic with stream
startup. This removes the race where a provider could emit events after
starting a stream but before the adapter subscribed.

Update the dependency:

```elixir
{:inference, "~> 0.4.0"}
```

Managed Gemini provider modules must implement `start_stream/3`, receiving the
prompt, provider options, and target process together, plus `stop_stream/1`.
The previous split `start_stream/2` and `subscribe_stream/1` protocol is no
longer used.

The adapter also maps known Gemini provider error categories to stable,
non-sensitive error reasons. Inference remains provider-neutral and adds no
provider SDK package dependency.
