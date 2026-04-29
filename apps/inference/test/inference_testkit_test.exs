defmodule InferenceTestkitTest do
  use ExUnit.Case, async: true

  alias Inference.Testkit.AdapterCase

  test "mock adapter satisfies basic text completion helper" do
    response =
      AdapterCase.assert_text_completion(Inference.Adapters.Mock,
        adapter_opts: [response_text: "testkit ok"]
      )

    assert response.text == "testkit ok"
  end

  test "unsupported stream helper works for non-stream adapters" do
    AdapterCase.assert_unsupported_stream(Inference.Adapters.GeminiEx,
      adapter_opts: [gemini_module: MissingGeminiForStream]
    )
  end

  test "redaction helper works" do
    redacted = AdapterCase.assert_redacts_metadata(%{token: "secret"})
    assert redacted.token == "[REDACTED]"
  end
end
