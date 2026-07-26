# Changelog

## Unreleased

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
