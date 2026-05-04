defmodule Inference.GovernedAuthorityTest do
  use ExUnit.Case, async: true

  alias Inference.{Client, Error, Trace}

  defmodule FakeReqLLM do
    def generate_text(model_spec, prompt, opts) do
      {:ok,
       %{
         id: "governed-req-1",
         text: "governed #{inspect(model_spec)} #{prompt}",
         opts: opts
       }}
    end
  end

  test "governed client rejects direct provider authority fields" do
    direct_fields = [
      provider: :openai,
      model: "direct-model",
      backend: :direct_backend,
      defaults: [api_key: "direct-key"],
      adapter_opts: [api_key: "direct-key"],
      api_key: "direct-key",
      provider_key: "direct-key",
      endpoint_auth: "direct-endpoint-key",
      service_identity: "direct-service",
      model_account: "direct-model-account",
      env: fn _key -> "direct-key" end
    ]

    for {field, value} <- direct_fields do
      assert {:error, %Error{category: :invalid, reason: :governed_authority} = error} =
               Client.new([{:governed_authority, authority()}, {field, value}])

      assert String.contains?(error.message, "direct governed client field")
      assert field in error.metadata.fields
    end
  end

  test "governed client materializes bounded adapter provider and model" do
    assert {:ok, client} = Client.new(governed_authority: authority())

    assert client.adapter == Inference.Adapters.Mock
    assert client.provider == :mock
    assert client.model == "governed-model"
    assert client.adapter_opts[:response_text] == "governed-ok"
    assert client.authority.authority_ref == "auth-inference"
    assert client.authority.credential_ref == "credential-inference"

    assert {:ok, response} = Inference.complete(client, "hello")
    assert response.trace.metadata.authority_ref == "auth-inference"
    assert response.trace.metadata.endpoint_ref == "endpoint-inference"
  end

  test "governed completion rejects request option smuggling before adapter dispatch" do
    client = Client.new!(governed_authority: authority())

    assert {:error, %Error{category: :invalid, reason: :governed_request_options} = error} =
             Inference.complete(client, "hello", options: [api_key: "direct-key"])

    assert :api_key in error.metadata.fields
  end

  test "governed ReqLLM compatibility adapter does not read unmanaged env" do
    client =
      Client.new!(
        governed_authority:
          authority(
            adapter_ref: "req_llm",
            provider_ref: "google",
            model: "gemini-governed",
            adapter_opts: [
              req_llm_module: FakeReqLLM,
              env: fn key ->
                send(self(), {:env_called, key})
                "ambient-key"
              end
            ]
          )
      )

    assert {:ok, response} = Inference.complete(client, "hello")
    refute_received {:env_called, _key}
    refute Keyword.has_key?(response.raw.opts, :api_key)
  end

  test "trace redaction removes exact authority selected values" do
    redacted =
      Trace.redact(%Trace{
        metadata: %{
          authority_ref: "auth-inference",
          note: "using secret-value from endpoint",
          redaction_values: ["secret-value"]
        }
      })

    assert redacted.metadata.authority_ref == "auth-inference"
    assert redacted.metadata.note == "using [REDACTED] from endpoint"
    assert redacted.metadata.redaction_values == ["[REDACTED]"]
  end

  defp authority(overrides \\ []) do
    %{
      authority_ref: "auth-inference",
      execution_context_ref: "execution-inference",
      adapter_ref: "mock",
      provider_ref: "mock",
      endpoint_ref: "endpoint-inference",
      provider_account_ref: "provider-account-inference",
      credential_ref: "credential-inference",
      target_ref: "target-inference",
      model_ref: "model-inference",
      service_identity_ref: "service-inference",
      model: "governed-model",
      adapter_opts: [response_text: "governed-ok"],
      redaction_values: ["secret-value"]
    }
    |> Map.merge(Map.new(overrides))
  end
end
