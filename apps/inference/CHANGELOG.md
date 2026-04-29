# Changelog

## 0.1.0-dev

- Initial project skeleton.
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
