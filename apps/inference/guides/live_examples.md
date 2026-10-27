# Live Examples

Default tests are mock-only. Live provider calls are demonstrated by the
repository-level `examples/*.exs` scripts. These scripts run directly and make
real provider calls when the underlying provider dependency and credentials are
available.

Run examples from the repository root:

```bash
elixir examples/live_gemini_ex.exs
```

## GeminiEx

```bash
export GEMINI_API_KEY=...
export INFERENCE_GEMINI_MODEL=gemini-3.1-flash-lite-preview
elixir examples/live_gemini_ex.exs
```

## Agent Session Manager

The completion-only examples use Claude or Codex. Amp, Antigravity, and Cursor
are recognized ASM providers, but Inference intentionally returns a typed
unsupported-capability error for them until their SDK feature manifests prove
completion-only execution.

```bash
elixir examples/asm_adapter/text_only.exs \
  --provider codex \
  --model gpt-6.1-sol \
  --prompt "Reply with exactly: INFERENCE_ASM_OK"

elixir examples/asm_adapter/tools_unsupported.exs \
  --provider codex \
  --model gpt-6.1-sol
```

The 0.5.2 release was verified on 2026-10-27 with a live query through
`Inference.Adapters.ASM`, ASM 0.17.4, and Codex SDK 0.21.4 on the `:sdk` lane.
GPT-6.1 Sol at low reasoning effort returned exactly `INFERENCE_052_CODEX_OK`.
This verifies the completion path; other provider paths were not live-tested
for this dependency refresh.

## ReqLlmNext

```bash
export GEMINI_API_KEY=...
export INFERENCE_REQLLM_NEXT_PROVIDER=google
export INFERENCE_REQLLM_NEXT_MODEL=gemini-3.1-flash-lite-preview
elixir examples/live_reqllm_next.exs
```

## ReqLLM Compatibility

Installs the latest compatible Hex package, currently `req_llm ~> 1.29.0`.

```bash
export GEMINI_API_KEY=... # or GOOGLE_API_KEY=...
export INFERENCE_REQ_LLM_PROVIDER=google
export INFERENCE_REQ_LLM_MODEL=gemini-3.1-flash-lite-preview
elixir examples/live_req_llm.exs
```
