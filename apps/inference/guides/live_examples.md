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
export GEMINI_API_KEY=...
export INFERENCE_ASM_PROVIDER=gemini
export INFERENCE_ASM_MODEL=gemini-3.1-flash-lite-preview
export INFERENCE_ASM_PROMPT="Say hello from ASM"
elixir examples/live_asm.exs
```

## ReqLlmNext

```bash
export GEMINI_API_KEY=...
export INFERENCE_REQLLM_NEXT_PROVIDER=google
export INFERENCE_REQLLM_NEXT_MODEL=gemini-3.1-flash-lite-preview
elixir examples/live_reqllm_next.exs
```

## ReqLLM Compatibility

```bash
export INFERENCE_REQ_LLM_PATH=/path/to/req_llm
export GEMINI_API_KEY=...
export INFERENCE_REQ_LLM_PROVIDER=gemini
export INFERENCE_REQ_LLM_MODEL=gemini-3.1-flash-lite-preview
elixir examples/live_req_llm.exs
```
