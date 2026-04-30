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

```bash
elixir examples/asm_adapter/text_only.exs \
  --provider codex \
  --model gpt-5.4 \
  --prompt "Reply with exactly: INFERENCE_ASM_OK"

elixir examples/asm_adapter/tools_unsupported.exs \
  --provider codex \
  --model gpt-5.4
```

## ReqLlmNext

```bash
export GEMINI_API_KEY=...
export INFERENCE_REQLLM_NEXT_PROVIDER=google
export INFERENCE_REQLLM_NEXT_MODEL=gemini-3.1-flash-lite-preview
elixir examples/live_reqllm_next.exs
```

## ReqLLM Compatibility

Installs the latest compatible Hex package, currently `req_llm ~> 1.10`.

```bash
export GEMINI_API_KEY=... # or GOOGLE_API_KEY=...
export INFERENCE_REQ_LLM_PROVIDER=google
export INFERENCE_REQ_LLM_MODEL=gemini-3.1-flash-lite-preview
elixir examples/live_req_llm.exs
```
