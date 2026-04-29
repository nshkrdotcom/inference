# Live Provider Examples

Tests in this repository use mocks and never call live providers.

Files in this directory are live examples. They are intentionally gated and can
talk to real provider/runtime libraries when you opt in with environment
variables and install the matching local provider repository.

Run examples from the repository root with `elixir`, not `mix test`.

## Common Gate

Every live example requires:

```bash
export INFERENCE_LIVE_EXAMPLES=1
```

Without that gate, examples exit before making provider calls.

## GeminiEx

Requires the local `gemini_ex` repository and a Gemini API key:

```bash
export INFERENCE_LIVE_EXAMPLES=1
export GEMINI_API_KEY=...
elixir examples/live_gemini_ex.exs
```

## Agent Session Manager

Requires the local `agent_session_manager` repository. Provider/session details
are passed through to ASM:

```bash
export INFERENCE_LIVE_EXAMPLES=1
export INFERENCE_ASM_PROVIDER=codex
export INFERENCE_ASM_PROMPT="Say hello from ASM"
elixir examples/live_asm.exs
```

## ReqLLM Compatibility

Requires a compatible `req_llm` dependency to be available to the script.

```bash
export INFERENCE_LIVE_EXAMPLES=1
export INFERENCE_REQ_LLM_PATH=/path/to/req_llm
export OPENAI_API_KEY=...
export INFERENCE_REQ_LLM_PROVIDER=openai
export INFERENCE_REQ_LLM_MODEL=gpt-4o-mini
elixir examples/live_req_llm.exs
```

## ReqLlmNext

Requires the local `reqllm_next` repository or an available package.

```bash
export INFERENCE_LIVE_EXAMPLES=1
export OPENAI_API_KEY=...
export INFERENCE_REQLLM_NEXT_PROVIDER=openai
export INFERENCE_REQLLM_NEXT_MODEL=gpt-4o-mini
elixir examples/live_reqllm_next.exs
```

## Jido

Jido governed execution is future work owned by `jido_integration`, not an
adapter shipped by `:inference`.
