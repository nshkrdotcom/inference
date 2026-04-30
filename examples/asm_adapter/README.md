# Inference ASM Adapter Examples

These examples belong to the `inference` repo because they exercise
`Inference.Adapters.ASM`. ASM links here but does not import or test these
examples.

## Examples

- `text_only.exs`: text-only inference through ASM strict common options.
- `tools_unsupported.exs`: explicit unsupported behavior for tool-bearing
  inference requests until ASM admits an all-provider host-tool contract.

## Live Commands

```bash
elixir examples/asm_adapter/text_only.exs \
  --provider codex \
  --model gpt-5.4 \
  --prompt "Reply with exactly: INFERENCE_ASM_OK"

elixir examples/asm_adapter/tools_unsupported.exs \
  --provider codex \
  --model gpt-5.4
```
