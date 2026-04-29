# Live Examples

Default tests are mock-only. Live provider calls are demonstrated by the
repository-level `examples/*.exs` scripts and require
`INFERENCE_LIVE_EXAMPLES=1`.

Run examples from the repository root:

```bash
export INFERENCE_LIVE_EXAMPLES=1
elixir examples/live_gemini_ex.exs
```

## GeminiEx

```bash
export INFERENCE_LIVE_EXAMPLES=1
export GEMINI_API_KEY=...
export INFERENCE_GEMINI_MODEL=gemini-2.0-flash
elixir examples/live_gemini_ex.exs
```

## Agent Session Manager

```bash
export INFERENCE_LIVE_EXAMPLES=1
export INFERENCE_ASM_PROVIDER=codex
export INFERENCE_ASM_PROMPT="Say hello from ASM"
elixir examples/live_asm.exs
```

## ReqLlmNext

```bash
export INFERENCE_LIVE_EXAMPLES=1
export OPENAI_API_KEY=...
export INFERENCE_REQLLM_NEXT_PROVIDER=openai
export INFERENCE_REQLLM_NEXT_MODEL=gpt-4o-mini
elixir examples/live_reqllm_next.exs
```

## ReqLLM Compatibility

```bash
export INFERENCE_LIVE_EXAMPLES=1
export INFERENCE_REQ_LLM_PATH=/path/to/req_llm
export OPENAI_API_KEY=...
export INFERENCE_REQ_LLM_PROVIDER=openai
export INFERENCE_REQ_LLM_MODEL=gpt-4o-mini
elixir examples/live_req_llm.exs
```

Without `INFERENCE_LIVE_EXAMPLES=1`, every live example exits before provider
dispatch.
