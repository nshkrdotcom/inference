# Inference ASM Adapter Examples

These examples belong to the `inference` repo because they exercise
`Inference.Adapters.ASM`. ASM links here but does not import or test these
examples.

Use Claude or Codex for successful completion-only calls. Amp, Antigravity, and
Cursor are valid ASM agent-session providers, but the Inference adapter refuses
them until their SDK feature manifests prove the completion-only contract.

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
