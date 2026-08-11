# Changelog

## Unreleased

## 0.4.0 - 2026-08-11

- Made managed Gemini stream startup and subscription atomic through
  `start_stream/3`, eliminating the event-delivery race in the previous split
  start/subscribe protocol.
- Mapped known Gemini provider errors onto stable, non-sensitive inference
  error reasons.
- Refreshed release metadata and provider-neutral installation guidance while
  preserving the package's zero provider-SDK dependency boundary.
- Fixed the packaged Mix project so it loads repository-only dependency-source
  tooling conditionally; the Hex archive now loads correctly without
  `build_support`.

## 0.3.0 - 2026-07-27

- Made the ASM adapter's completion, text, streaming, and structured-output
  capability claims derive from ASM's total common-feature manifest instead of
  assuming every recognized provider can satisfy inference semantics.
- Kept Claude and Codex enabled for completion-only ASM inference, while Amp,
  Antigravity, and Cursor now return a typed `:unsupported_capability` before
  query or stream dispatch.
- Covered all five ASM SDK providers in the capability and refusal matrix
  without adding provider SDK dependencies to the semantic inference package.
- Updated the shared dependency-source helper to the five-provider release DAG
  and prepared the `0.3.0` package, migration guide, and release metadata.

## 0.2.0 - 2026-07-27

- Publish preflight now verifies the exact local sibling release on Hex, so an
  older package version cannot falsely satisfy release readiness. Nested
  package tasks now resolve the workspace manifest instead of looking for one
  inside `apps/inference`, and manifest self-entries are excluded.
- Removed the outbound ASM strict-common preflight; ASM owns its own run-path
  option gate and the adapter no longer requires an `:asm_options_module`.
- Made `Inference.Request.response_format` a closed, validated union
  (`:text`, `{:json, :object}`, `{:json_schema, %{name:, schema:, strict:}}`).
  Every adapter now maps it or refuses with `:response_format_unsupported`.
- Mapped structured output through to providers: ASM `:output_schema`, Gemini
  `responseJsonSchema`/`responseMimeType`, ReqLLM `generate_object/4`.
- Switched the direct Gemini adapter to `Gemini.generate/2` and propagated the
  provider-reported object, usage, finish reason, response id, and model
  version; the managed Gemini adapter now accepts response formats and reports
  object output.
- Mapped `ASM.Error` kinds and `Gemini.Error` http statuses onto the declared
  error categories and preserved the provider error under
  `metadata.provider_error`.
- Added adapter-reported `Inference.Capability` claims and
  `Inference.capabilities/1`, including ASM's provider-declared
  `:structured_output` feature.
- Added `Inference.Client.agent_session/1` and `agent_session!/1` as the
  explicit agent-session opt-in; the default admitted-kind set is unchanged.
- Made completion-only explicit: ASM calls lock `completion_only: true`, Gemini
  requests refuse tool options, and a provider-returned tool call is a typed
  `:unexpected_tool_call` failure.
- Added `AdapterCase.assert_response_format_contract/2` and
  `assert_capability_contract/2` conformance helpers.

## 0.1.0 - 2026-07-13

- Initial project skeleton.
- Standardized Hex, HexDocs, changelog, and license release metadata.
- Added closed adapter provider kinds and explicit client admission so model
  endpoints remain the default while ASM agent sessions require opt-in.
- Documented `gemini_ex` as the distinct Gemini API SDK, Gemini CLI as retired,
  and Antigravity as the current Google coding-agent SDK behind ASM.
- Added semantic inference contracts.
- Added mock and optional provider adapter modules.
- Added live-gated provider examples.
- Expanded ReqLLM compatibility with structured object generation, provider key
  aliases, and portable tool conversion.
- Expanded ASM compatibility with managed streaming sessions and string-session
  routing.
- Added first-class response and trace cost fields, with shared extraction from
  provider map/struct results.
- Preserved ReqLLM tool-choice options and tool-call response fields through the
  compatibility adapter.
- Added ASM stream lifecycle coverage for early consumer halt and additional
  event-shape normalization.
- Fixed ASM prompt override handling so compatibility wrappers can preserve raw
  prompt text without forwarding internal `:prompt` options to Agent Session
  Manager.
