# Inference Buildout Checklist

Status: complete.

Scope: work only in this repository. The real package is
`apps/inference/mix.exs`.

## Phase 0 - Repository

- [x] Initialize git repository.
- [x] Create `nshkrdotcom/inference`.
- [x] Push `main`.
- [x] Add documented repository topics.

## Phase 1 - Skeleton

- [x] Create top-level `README.md`.
- [x] Create top-level `mix.exs`.
- [x] Create `apps/inference/assets/inference.svg`.
- [x] Create `apps/inference/README.md`.
- [x] Create `apps/inference/LICENSE`.
- [x] Create `apps/inference/CHANGELOG.md`.
- [x] Update `apps/inference/mix.exs`.
- [x] Add live example instructions.

## Phase 2 - Core Contracts

- [x] `Inference`
- [x] `Inference.Request`
- [x] `Inference.Message`
- [x] `Inference.Response`
- [x] `Inference.Client`
- [x] `Inference.Adapter`
- [x] `Inference.Capability`
- [x] `Inference.Error`
- [x] `Inference.StreamEvent`
- [x] `Inference.Trace`
- [x] `Inference.Redaction`

## Phase 3 - Testkit

- [x] `Inference.Testkit.AdapterCase`
- [x] successful text completion conformance helper
- [x] provider error normalization conformance helper
- [x] unsupported stream conformance helper
- [x] redaction conformance helper
- [x] trace metadata conformance helper

## Phase 4 - Adapter Modules

- [x] `Inference.Adapters.Mock`
- [x] `Inference.Adapters.ASM`
- [x] `Inference.Adapters.GeminiEx`
- [x] `Inference.Adapters.ReqLlmNext`
- [x] `Inference.Adapters.ReqLLM`

## Phase 5 - Live Examples

- [x] `examples/README.md`
- [x] `examples/live_gemini_ex.exs`
- [x] `examples/live_asm.exs`
- [x] `examples/live_req_llm.exs`
- [x] `examples/live_reqllm_next.exs`

## Future Roadmap Outside This Repo

- [ ] Trinity consumes `:inference`.
- [ ] GEPA consumes `:inference`.
- [ ] `jido_integration` implements a Jido-owned `Inference.Adapter` bridge.

## Final Gates

- [x] initial skeleton commit pushed
- [x] `mix format --check-formatted`
- [x] `cd apps/inference && mix compile --warnings-as-errors`
- [x] `cd apps/inference && mix test`
- [x] `cd apps/inference && mix credo --strict`
- [x] `cd apps/inference && mix dialyzer`
- [x] `cd apps/inference && mix docs`
- [x] live examples run directly without an extra enablement gate
