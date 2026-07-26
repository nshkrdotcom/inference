# Live Provider Examples

Tests in this repository use mocks and never call live providers.

Files in this directory are live examples. They run directly and attempt real
provider/runtime calls. Configure the provider credentials required by the
underlying library before running them.

Run examples from the repository root with `elixir`, not `mix test`.

## Concurrent Provider Race

The text race launches GeminiEx, Claude Agent SDK through ASM, and Codex SDK
through ASM concurrently. It prints each real response as it finishes:

```bash
export GEMINI_API_KEY=...
elixir examples/live_provider_race.exs
```

The structured race sends the same three providers a strict JSON Schema and
requires `%{"message" => "hello"}` to reach `Inference.Response.object`:

```bash
export GEMINI_API_KEY=...
elixir examples/live_structured_provider_race.exs
```

Both scripts force the Claude and Codex SDK lanes, use their existing local CLI
authentication, and fail if any provider does not return the expected response.
Optional model overrides are `INFERENCE_RACE_GEMINI_MODEL`,
`INFERENCE_RACE_CLAUDE_MODEL`, and `INFERENCE_RACE_CODEX_MODEL`.

## GeminiEx

Requires the local `gemini_ex` repository and a Gemini API key:

```bash
export GEMINI_API_KEY=...
elixir examples/live_gemini_ex.exs
```

## Agent Session Manager

Requires the local `agent_session_manager` repository. Provider/session details
are passed through to ASM.

The ASM adapter is common-only. Provider-native tool controls are rejected until
ASM has a proven all-provider host-tool contract.

```bash
elixir examples/asm_adapter/text_only.exs \
  --provider codex \
  --model gpt-5.4 \
  --prompt "Reply with exactly: INFERENCE_ASM_OK"

elixir examples/asm_adapter/tools_unsupported.exs \
  --provider codex \
  --model gpt-5.4
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

Jido governed execution is required platform scope owned by
`jido_integration`, not an adapter shipped by `:inference`. Direct examples in
this repository remain standalone provider examples. Governed live-provider
proof must run through the Jido-owned adapter with authority refs, credential
handles or leases, target grants, disposable credentials, and cleanup evidence.
