Mix.install([
  {:inference, path: Path.expand("../apps/inference", __DIR__)},
  {:agent_session_manager, path: Path.expand("../../agent_session_manager", __DIR__)},
  {:claude_agent_sdk, path: Path.expand("../../claude_agent_sdk", __DIR__)},
  {:codex_sdk, path: Path.expand("../../codex_sdk", __DIR__)},
  {:gemini_ex, path: Path.expand("../../gemini_ex", __DIR__)}
])

Code.require_file("support/live_provider_race.exs", __DIR__)

InferenceExamples.LiveProviderRace.run!(:text)
