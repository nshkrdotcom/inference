defmodule Elixir.Gemini.Error do
  @moduledoc false
  # Hand-written stand-in for the real `Gemini.Error` struct in
  # `/home/home/p/g/n/gemini_ex/lib/gemini/error.ex`.

  defexception [:type, :message, :http_status, :api_reason, :details, :original_error]
end

defmodule Inference.Adapters.GeminiExTest do
  use ExUnit.Case, async: true

  alias Inference.Adapters.GeminiEx
  alias Inference.{Capability, Client, Error}

  defmodule FakeGemini do
    @moduledoc false

    def text(prompt, opts) do
      send(self(), {:gemini_text, prompt, opts})
      {:ok, "text/2 must not be used"}
    end

    def generate(prompt, opts) do
      send(self(), {:gemini_generate, prompt, opts})

      case Keyword.get(opts, :fail_with) do
        nil -> {:ok, Keyword.get(opts, :reply, default_reply())}
        reason -> {:error, reason}
      end
    end

    defp default_reply do
      %{
        response_id: "resp-1",
        model_version: "gemini-3.1-flash",
        candidates: [
          %{
            content: %{parts: [%{text: "structured reply"}]},
            finish_reason: "STOP"
          }
        ],
        usage_metadata: %{
          prompt_token_count: 3,
          candidates_token_count: 2,
          total_token_count: 5,
          cached_content_token_count: 1,
          thoughts_token_count: 4
        }
      }
    end
  end

  defmodule TextOnlyGemini do
    @moduledoc false
    def text(_prompt, _opts), do: {:ok, "text only"}
  end

  defp client(opts \\ []) do
    {gemini_module, defaults} = Keyword.pop(opts, :gemini_module, FakeGemini)

    Client.new!(
      adapter: GeminiEx,
      provider: :gemini,
      model: "gemini-3.1-flash",
      defaults: defaults,
      adapter_opts: [gemini_module: gemini_module]
    )
  end

  describe "INF-3b the adapter uses the structured provider call" do
    test "a completion propagates id, model version, usage, and finish reason" do
      assert {:ok, response} = Inference.complete(client(), "hello")

      assert response.text == "structured reply"
      assert response.id == "resp-1"
      assert response.provider == :gemini
      assert response.finish_reason == "STOP"

      assert response.usage == %{
               input_tokens: 3,
               output_tokens: 2,
               total_tokens: 5,
               cached_tokens: 1,
               thoughts_tokens: 4
             }

      assert response.metadata.model_version == "gemini-3.1-flash"
      refute is_binary(response.raw)
      assert response.raw.response_id == "resp-1"
    end

    test "the raw API response shape is understood too" do
      reply = %{
        "responseId" => "resp-2",
        "modelVersion" => "gemini-3.1-pro",
        "candidates" => [
          %{"content" => %{"parts" => [%{"text" => "raw reply"}]}, "finishReason" => "STOP"}
        ],
        "usageMetadata" => %{"promptTokenCount" => 1, "totalTokenCount" => 2}
      }

      assert {:ok, response} = Inference.complete(client(reply: reply), "hello")
      assert response.text == "raw reply"
      assert response.id == "resp-2"
      assert response.usage == %{input_tokens: 1, total_tokens: 2}
      assert response.metadata.model_version == "gemini-3.1-pro"
    end

    test "Gemini.text/2 is never used" do
      assert {:ok, _response} = Inference.complete(client(), "hello")
      assert_received {:gemini_generate, "hello", _opts}
      refute_received {:gemini_text, _prompt, _opts}
    end

    test "a module without generate/2 is a missing dependency, not a text fallback" do
      assert {:error, %Error{category: :missing_dependency} = error} =
               Inference.complete(client(gemini_module: TextOnlyGemini), "hello")

      assert error.metadata.details[:function] == :generate
    end

    test "max tokens reach the provider under its own option name" do
      assert {:ok, _response} = Inference.complete(client(), "hello", max_tokens: 128)
      assert_received {:gemini_generate, _prompt, opts}
      assert opts[:max_output_tokens] == 128
      refute Keyword.has_key?(opts, :max_tokens)
    end
  end

  describe "INF-3 response_format mapping" do
    test "a json schema response format becomes responseJsonSchema generation config" do
      schema = %{"type" => "object", "properties" => %{"answer" => %{"type" => "string"}}}

      reply = %{
        candidates: [%{content: %{parts: [%{text: ~s({"answer":"42"})}]}, finish_reason: "STOP"}]
      }

      assert {:ok, response} =
               Inference.complete(client(reply: reply), "hello",
                 response_format: {:json_schema, %{name: "answer", schema: schema}}
               )

      assert_received {:gemini_generate, _prompt, opts}
      assert opts[:response_json_schema] == schema
      assert opts[:response_mime_type] == "application/json"
      refute Keyword.has_key?(opts, :response_format)

      assert response.object == %{"answer" => "42"}
      assert response.text == ~s({"answer":"42"})
    end

    test "json object mode asks for the json mime type without a schema" do
      reply = %{candidates: [%{content: %{parts: [%{text: ~s({"a":1})}]}}]}

      assert {:ok, response} =
               Inference.complete(client(reply: reply), "hello",
                 response_format: {:json, :object}
               )

      assert_received {:gemini_generate, _prompt, opts}
      assert opts[:response_mime_type] == "application/json"
      refute Keyword.has_key?(opts, :response_json_schema)
      assert response.object == %{"a" => 1}
    end

    test "undecodable structured output leaves object empty instead of inventing one" do
      reply = %{candidates: [%{content: %{parts: [%{text: "not json"}]}}]}

      assert {:ok, response} =
               Inference.complete(client(reply: reply), "hello",
                 response_format: {:json, :object}
               )

      assert response.text == "not json"
      assert response.object == nil
    end

    test "a keyword schema is refused because Gemini takes a JSON Schema map" do
      assert {:error, %Error{reason: :response_format_unsupported} = error} =
               Inference.complete(client(), "hello",
                 response_format:
                   {:json_schema, %{name: "answer", schema: [answer: [type: :string]]}}
               )

      assert error.category == :unsupported_capability
      refute_received {:gemini_generate, _prompt, _opts}
    end

    test "plain text needs no generation config" do
      assert {:ok, _response} = Inference.complete(client(), "hello", response_format: :text)
      assert_received {:gemini_generate, _prompt, opts}
      refute Keyword.has_key?(opts, :response_mime_type)
      refute Keyword.has_key?(opts, :response_json_schema)
    end
  end

  describe "INF-7 completion-only adapter" do
    test "tool options are rejected before dispatch" do
      for key <- [:tools, :tool_choice, :tool_config, :function_declarations] do
        assert {:error, %Error{category: :unsupported_capability} = error} =
                 Inference.complete(client(), "hello", options: [{key, []}])

        assert error.metadata.key == key
        refute_received {:gemini_generate, _prompt, _opts}
      end
    end

    test "a returned function call is a typed contract failure" do
      reply = %{
        candidates: [
          %{
            content: %{
              parts: [%{function_call: %{name: "lookup", args: %{"query" => "hello"}}}]
            }
          }
        ]
      }

      assert {:error, %Error{category: :invalid_response, reason: :unexpected_tool_call} = error} =
               Inference.complete(client(reply: reply), "hello")

      assert error.metadata.tool_calls == [%{name: "lookup", args: %{"query" => "hello"}}]
    end
  end

  describe "INF-4 provider error mapping" do
    test "http status and error type map onto the declared categories" do
      for {attrs, category, reason} <- [
            {[type: :api_error, http_status: 429], :rate_limited, :api_error},
            {[type: :api_error, http_status: 401], :missing_credentials, :api_error},
            {[type: :api_error, http_status: 408], :timeout, :api_error},
            {[type: :api_error, http_status: 400], :invalid, :api_error},
            {[type: :api_error, http_status: 503], :provider_error, :api_error},
            {[type: :auth_error], :missing_credentials, :auth_error},
            {[type: :config_error], :invalid, :config_error},
            {[type: :validation_error], :invalid, :validation_error},
            {[type: :serialization_error], :invalid_response, :serialization_error},
            {[type: :invalid_response], :invalid_response, :invalid_response},
            {[type: :network_error], :provider_error, :network_error}
          ] do
        gemini_error = struct!(Gemini.Error, [message: "boom"] ++ attrs)
        client = client(fail_with: gemini_error)

        assert {:error, %Error{} = error} = Inference.complete(client, "hello")

        assert error.category == category,
               "expected #{inspect(attrs)} to map to #{inspect(category)}, got #{inspect(error.category)}"

        assert error.reason == reason
        assert error.metadata.provider_error == gemini_error
        assert error.message =~ "boom"
      end
    end

    test "the http status is preserved in metadata" do
      gemini_error = %Gemini.Error{type: :api_error, message: "quota", http_status: 429}

      assert {:error, %Error{} = error} =
               Inference.complete(client(fail_with: gemini_error), "hello")

      assert error.metadata.provider_http_status == 429
    end
  end

  describe "INF-5 capabilities" do
    test "the adapter answers structured-output questions before dispatch" do
      capabilities = Inference.capabilities(client())

      assert Capability.supported?(capabilities, :response_format_json_schema)
      assert Capability.supported?(capabilities, :response_format_json_object)
      assert Capability.supported?(capabilities, :response_format_text)
      refute Capability.supported?(capabilities, :tools)
      refute Capability.supported?(capabilities, :streaming)

      assert %Capability{metadata: %{generation_option: :response_json_schema}} =
               Capability.fetch!(capabilities, :response_format_json_schema)
    end
  end
end
