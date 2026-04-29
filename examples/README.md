# Live Provider Examples

Tests in this repository use mocks and never call live providers.

Files in this directory are live examples. They run directly and attempt real
provider/runtime calls. Configure the provider credentials required by the
underlying library before running them.

Run examples from the repository root with `elixir`, not `mix test`.

## GeminiEx

Requires the local `gemini_ex` repository and a Gemini API key:

```bash
export GEMINI_API_KEY=...
elixir examples/live_gemini_ex.exs
```

## Agent Session Manager

Requires the local `agent_session_manager` repository. Provider/session details
are passed through to ASM:

```bash
export GEMINI_API_KEY=...
export INFERENCE_ASM_PROVIDER=gemini
export INFERENCE_ASM_MODEL=gemini-3.1-flash-lite-preview
export INFERENCE_ASM_PROMPT="Say hello from ASM"
elixir examples/live_asm.exs
```

## ReqLLM Compatibility

Installs the latest compatible Hex package, currently `req_llm ~> 1.10`.

```bash
export GEMINI_API_KEY=... # or GOOGLE_API_KEY=...
export INFERENCE_REQ_LLM_PROVIDER=google
export INFERENCE_REQ_LLM_MODEL=gemini-3.1-flash-lite-preview
elixir examples/live_req_llm.exs
```

## ReqLlmNext

Requires the local `reqllm_next` repository or an available package.

```bash
export GEMINI_API_KEY=...
export INFERENCE_REQLLM_NEXT_PROVIDER=google
export INFERENCE_REQLLM_NEXT_MODEL=gemini-3.1-flash-lite-preview
elixir examples/live_reqllm_next.exs
```

## Jido

Jido governed execution is future work owned by `jido_integration`, not an
adapter shipped by `:inference`.
