defmodule InferenceTest do
  use ExUnit.Case, async: true

  alias Inference.{Client, Error, Message, Request, Response}

  defmodule FakeGemini do
    def text(prompt, opts), do: {:ok, "gemini: #{prompt} #{opts[:model]}"}
  end

  defmodule FakeASMResult do
    defstruct [
      :id,
      :text,
      :usage,
      :finish_reason,
      :run_id,
      :session_id,
      :duration_ms,
      :cost,
      :metadata
    ]
  end

  defmodule FakeASMChunk do
    defstruct [:content]

    def assistant_text(%__MODULE__{content: content}), do: content
  end

  defmodule FakeASMOptions do
    @provider_native_keys [:system_prompt, :settings, :host_tools, :dynamic_tools, :env, :args]

    def preflight(provider, opts, mode: :strict_common) do
      send(self(), {:asm_preflight, provider, opts})

      case Enum.find(@provider_native_keys, &Keyword.has_key?(opts, &1)) do
        nil ->
          {:ok,
           %{
             provider: provider,
             mode: :strict_common,
             common: Map.new(opts),
             session: %{},
             partial: %{},
             provider_native_legacy: %{},
             rejected: [],
             warnings: []
           }}

        key ->
          {:error, Error.invalid(:asm_options, "ASM strict preflight rejected #{inspect(key)}")}
      end
    end
  end

  defmodule FakeASM do
    def query(provider, prompt, opts) do
      send(self(), {:asm_query, provider, prompt, opts})

      {:ok,
       %FakeASMResult{
         text: "asm #{provider}: #{prompt}",
         run_id: "run-1",
         session_id: "session-1",
         duration_ms: 12,
         cost: %{usd: 0},
         usage: %{input_tokens: 1, output_tokens: 2},
         finish_reason: opts[:finish_reason] || :stop,
         metadata: %{opts: opts}
       }}
    end

    def start_session(opts) do
      send(self(), {:start_session, opts})
      {:ok, self()}
    end

    def stream(session, _prompt, opts) when is_pid(session) do
      case opts[:shape] do
        :assistant_struct -> [%FakeASMChunk{content: "struct-delta"}, %{message: "map-message"}]
        _other -> [%{text: "a"}, "b"]
      end
    end

    def stop_session(session) do
      send(self(), {:stop_session, session})
      :ok
    end
  end

  defmodule FakeReqLlmNext do
    def generate_text(model_spec, prompt, _opts) do
      {:ok, %{id: "req-next-1", text: "next #{model_spec}: #{prompt}", usage: %{tokens: 3}}}
    end
  end

  defmodule FakeReqLLM do
    def put_key(key, value) do
      send(self(), {:put_key, key, value})
      :ok
    end

    def generate_text(model_spec, prompt, opts) do
      {:ok,
       %{
         id: "req-llm-1",
         text: "req #{inspect(model_spec)}: #{prompt}",
         usage: %{input_tokens: 1, output_tokens: 2},
         cost: %{usd: 0.001},
         tool_calls: [%{id: "call-1", name: "lookup", arguments: %{"query" => "hello"}}],
         model_spec: model_spec,
         opts: opts
       }}
    end

    def generate_object(model_spec, prompt, schema, opts) do
      {:ok,
       %{
         id: "req-llm-object-1",
         object: %{"instruction" => "structured #{inspect(model_spec)}: #{prompt}"},
         schema: schema,
         opts: opts
       }}
    end
  end

  defmodule FakeReqLLMResponse do
    def unwrap_object(%{object: object}), do: {:ok, object}
  end

  defmodule Elixir.ReqLLM.Tool do
    defstruct [:name, :description, :parameter_schema, :callback]

    def new(opts), do: {:ok, struct!(__MODULE__, opts)}
  end

  defmodule FakeTool do
    defstruct [:name, :description, :input_schema, :run]
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
        adapter_opts: [asm_module: FakeASM, asm_options_module: FakeASMOptions]
      )

    assert {:ok, response} = Inference.complete(client, "hello")
    assert response.text =~ "asm codex"
    assert response.metadata.run_id == "run-1"
    assert_received {:asm_preflight, :codex, opts}
    assert opts[:model] == "codex"
    refute Keyword.has_key?(opts, :provider)
  end

  test "asm adapter uses internal prompt override without forwarding it as provider option" do
    client =
      Client.new!(
        adapter: Inference.Adapters.ASM,
        provider: :codex,
        model: "codex",
        adapter_opts: [asm_module: FakeASM, asm_options_module: FakeASMOptions]
      )

    assert {:ok, response} = Inference.complete(client, "hello", options: [prompt: "raw prompt"])
    assert response.text =~ "asm codex: raw prompt"
    refute Keyword.has_key?(response.metadata.opts, :prompt)
  end

  test "asm adapter rejects tool requests until ASM has a common tool contract" do
    client =
      Client.new!(
        adapter: Inference.Adapters.ASM,
        provider: :codex,
        model: "codex",
        adapter_opts: [asm_module: FakeASM, asm_options_module: FakeASMOptions]
      )

    assert {:error, %Error{category: :unsupported_capability} = error} =
             Inference.complete(client, "hello", options: [tools: [%{name: "lookup"}]])

    assert error.message =~ "ASM adapter does not support inference tools"
    refute_received {:asm_query, _provider, _prompt, _opts}
  end

  test "asm adapter rejects provider-native tool keys from adapter query opts" do
    client =
      Client.new!(
        adapter: Inference.Adapters.ASM,
        provider: :codex,
        model: "codex",
        adapter_opts: [
          asm_module: FakeASM,
          asm_options_module: FakeASMOptions,
          query_opts: [dynamic_tools: [%{name: "lookup"}]]
        ]
      )

    assert {:error, %Error{category: :unsupported_capability} = error} =
             Inference.complete(client, "hello")

    assert error.message =~ ":dynamic_tools"
    refute_received {:asm_query, _provider, _prompt, _opts}
  end

  test "asm adapter routes generic options through ASM strict preflight" do
    client =
      Client.new!(
        adapter: Inference.Adapters.ASM,
        provider: :gemini,
        model: "gemini-model",
        adapter_opts: [
          asm_module: FakeASM,
          asm_options_module: FakeASMOptions,
          query_opts: [system_prompt: "provider-native"]
        ]
      )

    assert {:error, %Error{category: :invalid, reason: :asm_options}} =
             Inference.complete(client, "hello")

    assert_received {:asm_preflight, :gemini, opts}
    assert opts[:system_prompt] == "provider-native"
    refute_received {:asm_query, _provider, _prompt, _opts}
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

    assert {:ok, response} = Inference.complete(client, "hello", temperature: 0.2)
    assert response.text =~ "req %{"
    assert response.raw.model_spec == %{provider: :openai, id: "gpt-test"}
    assert response.raw.opts[:temperature] == 0.2
    refute Keyword.has_key?(response.raw.opts, :model)
  end

  test "req llm compatibility adapter propagates usage, cost, and tool call fields" do
    client =
      Client.new!(
        adapter: Inference.Adapters.ReqLLM,
        provider: :openai,
        model: "gpt-test",
        adapter_opts: [req_llm_module: FakeReqLLM]
      )

    assert {:ok, response} =
             Inference.complete(client, "hello", options: [tool_choice: :required])

    assert response.usage == %{input_tokens: 1, output_tokens: 2}
    assert response.cost == %{usd: 0.001}

    assert response.tool_calls == [
             %{id: "call-1", name: "lookup", arguments: %{"query" => "hello"}}
           ]

    assert response.raw.opts[:tool_choice] == :required
  end

  test "req llm adapter supports structured object generation and provider keys" do
    client =
      Client.new!(
        adapter: Inference.Adapters.ReqLLM,
        provider: :gemini,
        model: "gemini-test",
        adapter_opts: [
          req_llm_module: FakeReqLLM,
          response_module: FakeReqLLMResponse,
          env: fn
            "GEMINI_API_KEY" -> "gemini-key"
            _key -> nil
          end
        ]
      )

    assert {:ok, response} =
             Inference.complete(client, "hello",
               response_format: [instruction: [type: :string, required: true]]
             )

    assert response.object["instruction"] =~ "structured %{"
    assert response.object["instruction"] =~ "provider: :gemini"
    assert response.object["instruction"] =~ "id: \"gemini-test\""
    assert response.object["instruction"] =~ "user: hello"

    assert response.raw.opts[:api_key] == "gemini-key"
    assert_received {:put_key, :google_api_key, "gemini-key"}
  end

  test "req llm adapter converts portable tool structs when ReqLLM.Tool is available" do
    client =
      Client.new!(
        adapter: Inference.Adapters.ReqLLM,
        provider: :openai,
        model: "gpt-test",
        adapter_opts: [req_llm_module: FakeReqLLM]
      )

    tool = %FakeTool{
      name: "lookup",
      description: "Look up a value",
      input_schema: [query: [type: :string, required: true]],
      run: fn args, _context -> {:ok, args} end
    }

    assert {:ok, response} =
             Inference.complete(client, "hello", options: [tools: [tool], tool_choice: :auto])

    assert [%ReqLLM.Tool{name: "lookup"}] = response.raw.opts[:tools]
    assert response.raw.opts[:tool_choice] == :auto
  end

  test "asm adapter streams with managed sessions and closes them" do
    client =
      Client.new!(
        adapter: Inference.Adapters.ASM,
        provider: :codex,
        model: "codex-model",
        defaults: [lane: :core],
        adapter_opts: [
          asm_module: FakeASM,
          asm_options_module: FakeASMOptions,
          session: "session-name"
        ]
      )

    assert {:ok, stream} = Inference.stream(client, "hello")
    assert Enum.map(stream, & &1.data) == ["a", "b"]
    assert_received {:start_session, opts}
    assert opts[:provider] == :codex
    assert opts[:session_id] == "session-name"
    refute Keyword.has_key?(opts, :prompt)
    assert opts[:lane] == :core
    assert_received {:stop_session, pid} when pid == self()
  end

  test "asm adapter closes managed stream sessions when consumers halt early" do
    client =
      Client.new!(
        adapter: Inference.Adapters.ASM,
        provider: :codex,
        model: "codex-model",
        defaults: [lane: :core],
        adapter_opts: [
          asm_module: FakeASM,
          asm_options_module: FakeASMOptions,
          session: "session-name"
        ]
      )

    assert {:ok, stream} = Inference.stream(client, "hello")
    assert [%Inference.StreamEvent{data: "a"}] = Enum.take(stream, 1)
    assert_received {:stop_session, pid} when pid == self()
  end

  test "asm adapter does not close externally supplied stream sessions" do
    client =
      Client.new!(
        adapter: Inference.Adapters.ASM,
        provider: :codex,
        model: "codex-model",
        defaults: [lane: :core],
        adapter_opts: [asm_module: FakeASM, asm_options_module: FakeASMOptions, session: self()]
      )

    assert {:ok, stream} = Inference.stream(client, "hello")
    assert Enum.map(stream, & &1.data) == ["a", "b"]
    refute_received {:stop_session, _pid}
  end

  test "asm adapter normalizes assistant structs and message maps into stream deltas" do
    client =
      Client.new!(
        adapter: Inference.Adapters.ASM,
        provider: :codex,
        model: "codex-model",
        defaults: [lane: :core],
        adapter_opts: [
          asm_module: FakeASM,
          asm_options_module: FakeASMOptions,
          session: "session-name",
          stream_opts: [shape: :assistant_struct]
        ]
      )

    assert {:ok, stream} = Inference.stream(client, "hello")
    assert Enum.map(stream, & &1.data) == ["struct-delta", "map-message"]
    assert_received {:stop_session, pid} when pid == self()
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
