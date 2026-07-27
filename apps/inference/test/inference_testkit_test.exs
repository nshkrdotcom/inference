defmodule InferenceTestkitTest do
  use ExUnit.Case, async: true

  alias Inference.Adapters.{ASM, GeminiEx, GeminiExManaged, Mock, ReqLLM, ReqLlmNext}
  alias Inference.Testkit.AdapterCase

  defmodule ConformanceGemini do
    @moduledoc false
    def generate(_prompt, _opts) do
      {:ok, %{candidates: [%{content: %{parts: [%{text: ~s({"answer":"42"})}]}}]}}
    end
  end

  defmodule ConformanceASM do
    @moduledoc false
    def query(_target, _prompt, _opts), do: {:ok, %{text: "asm reply"}}
  end

  defmodule ConformanceReqLLM do
    @moduledoc false
    def generate_text(_model_spec, _prompt, _opts), do: {:ok, %{text: "req reply"}}

    def generate_object(_model_spec, _prompt, _schema, _opts),
      do: {:ok, %{object: %{"answer" => "42"}}}
  end

  defmodule ConformanceReqLlmNext do
    @moduledoc false
    def generate_text(_model_spec, _prompt, _opts), do: {:ok, %{text: "next reply"}}
  end

  test "mock adapter satisfies basic text completion helper" do
    response =
      AdapterCase.assert_text_completion(Mock, adapter_opts: [response_text: "testkit ok"])

    assert response.text == "testkit ok"
  end

  test "unsupported stream helper works for non-stream adapters" do
    AdapterCase.assert_unsupported_stream(GeminiEx,
      adapter_opts: [gemini_module: MissingGeminiForStream]
    )
  end

  test "redaction helper works" do
    redacted = AdapterCase.assert_redacts_metadata(%{token: "secret"})
    assert redacted.token == "[REDACTED]"
  end

  test "every built-in adapter either maps or refuses a declared response format" do
    for {adapter, opts} <- [
          {Mock, [adapter_opts: [response_object: %{"answer" => "42"}]]},
          {Mock, []},
          {GeminiEx, [adapter_opts: [gemini_module: ConformanceGemini]]},
          {ASM, [adapter_opts: [asm_module: ConformanceASM]]},
          {ReqLLM, [adapter_opts: [req_llm_module: ConformanceReqLLM]]},
          {ReqLlmNext, [adapter_opts: [executor_module: ConformanceReqLlmNext]]}
        ] do
      AdapterCase.assert_response_format_contract(adapter, opts)
    end
  end

  test "capability-reporting adapters answer the structured-output question before dispatch" do
    required = [
      :response_format_text,
      :response_format_json_object,
      :response_format_json_schema,
      :tools,
      :streaming
    ]

    for adapter <- [ASM, GeminiEx, GeminiExManaged] do
      AdapterCase.assert_capability_contract(adapter, require: required)
    end

    AdapterCase.assert_capability_contract(ASM, require: [:completion_only])
  end
end
