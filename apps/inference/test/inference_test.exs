defmodule InferenceTest do
  use ExUnit.Case, async: true

  alias Inference.{Client, Error, Message, Request, Response}

  defmodule FakeGemini do
    def text(prompt, opts), do: {:ok, "gemini: #{prompt} #{opts[:model]}"}
  end

  defmodule FakeASMResult do
    defstruct [:id, :text, :usage, :finish_reason, :run_id, :session_id, :duration_ms, :cost]
  end

  defmodule FakeASM do
    def query(provider, prompt, opts) do
      {:ok,
       %FakeASMResult{
         text: "asm #{provider}: #{prompt}",
         run_id: "run-1",
         session_id: "session-1",
         duration_ms: 12,
         cost: %{usd: 0},
         usage: %{input_tokens: 1, output_tokens: 2},
         finish_reason: opts[:finish_reason] || :stop
       }}
    end
  end

  defmodule FakeReqLlmNext do
    def generate_text(model_spec, prompt, _opts) do
      {:ok, %{id: "req-next-1", text: "next #{model_spec}: #{prompt}", usage: %{tokens: 3}}}
    end
  end

  defmodule FakeReqLLM do
    def generate_text(model_spec, prompt, _opts) do
      {:ok, %{id: "req-llm-1", text: "req #{inspect(model_spec)}: #{prompt}"}}
    end
  end

  test "request can be built from prompt text" do
    assert {:ok, %Request{messages: [%Message{role: :user, content: "hello"}]}} =
             Request.from_prompt("hello")
  end

  test "request can be built from role content messages" do
    assert {:ok, %Request{messages: [%Message{role: :system}, %Message{role: :user}]}} =
             Request.from_messages([
               %{role: :system, content: "be terse"},
               %{role: "user", content: "hello"}
             ])
  end

  test "invalid role fails before provider dispatch" do
    assert {:error, %Error{category: :invalid, reason: :role}} =
             Request.from_messages([%{role: :bad, content: "hello"}])
  end

  test "invalid content fails before provider dispatch" do
    assert {:error, %Error{category: :invalid, reason: :content}} =
             Request.from_messages([%{role: :user, content: ""}])
  end

  test "nil response text normalizes to empty string" do
    assert "" == Response.text(Response.new(text: nil))
  end

  test "redaction removes API-key-like values from metadata" do
    redacted =
      Inference.Redaction.redact(%{api_key: "secret", nested: %{authorization: "secret"}})

    assert redacted.api_key == "[REDACTED]"
    assert redacted.nested.authorization == "[REDACTED]"
  end

  test "mock adapter returns response through facade" do
    client =
      Client.new!(
        adapter: Inference.Adapters.Mock,
        provider: :mock,
        model: "mock-fast",
        adapter_opts: [response_text: "fixed"]
      )

    assert {:ok, response} = Inference.complete(client, "hello")
    assert response.text == "fixed"
    assert response.provider == :mock
    assert response.model == "mock-fast"
  end

  test "mock adapter supports stream events" do
    client = Client.new!(adapter: Inference.Adapters.Mock, provider: :mock)
    assert {:ok, events} = Inference.stream(client, "hello")
    assert Enum.map(events, & &1.type) == [:delta, :done]
  end

  test "gemini adapter works with fake module" do
    client =
      Client.new!(
        adapter: Inference.Adapters.GeminiEx,
        provider: :gemini,
        model: "gemini-test",
        adapter_opts: [gemini_module: FakeGemini]
      )

    assert {:ok, response} = Inference.complete(client, "hello")
    assert response.text =~ "gemini:"
  end

  test "asm adapter works with fake module" do
    client =
      Client.new!(
        adapter: Inference.Adapters.ASM,
        provider: :codex,
        model: "codex",
        adapter_opts: [asm_module: FakeASM]
      )

    assert {:ok, response} = Inference.complete(client, "hello")
    assert response.text =~ "asm codex"
    assert response.metadata.run_id == "run-1"
  end

  test "reqllm next adapter works with fake module" do
    client =
      Client.new!(
        adapter: Inference.Adapters.ReqLlmNext,
        provider: :openai,
        model: "gpt-test",
        adapter_opts: [executor_module: FakeReqLlmNext]
      )

    assert {:ok, response} = Inference.complete(client, "hello")
    assert response.text =~ "next openai:gpt-test"
  end

  test "req llm compatibility adapter works with fake module" do
    client =
      Client.new!(
        adapter: Inference.Adapters.ReqLLM,
        provider: :openai,
        model: "gpt-test",
        adapter_opts: [req_llm_module: FakeReqLLM]
      )

    assert {:ok, response} = Inference.complete(client, "hello")
    assert response.text =~ "req %{"
  end

  test "external adapter returns missing dependency when module is absent" do
    client =
      Client.new!(
        adapter: Inference.Adapters.GeminiEx,
        provider: :gemini,
        adapter_opts: [gemini_module: DefinitelyMissingGeminiModule]
      )

    assert {:error, %Error{category: :missing_dependency}} = Inference.complete(client, "hello")
  end
end
