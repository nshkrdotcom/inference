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

  defmodule FakeASMResult do
    defstruct [:text, :metadata]
  end

  defmodule FakeASMOptions do
    def preflight(provider, opts, mode: :strict_common) do
      send(self(), {:asm_preflight, provider, opts})
      {:ok, %{provider: provider, mode: :strict_common, common: Map.new(opts)}}
    end
  end

  defmodule FakeASM do
    def query(provider, prompt, opts) do
      send(self(), {:asm_query, provider, prompt, opts})
      {:ok, %FakeASMResult{text: "asm #{provider}: #{prompt}", metadata: %{opts: opts}}}
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
    assert client.authority.credential_handle_ref == "credential-handle-inference"
    assert client.authority.credential_lease_ref == "credential-lease-inference"
    assert client.authority.target_posture_ref == "target-posture-inference"
    assert client.authority.attach_grant_ref == "attach-grant-inference"
    assert client.authority.operation_policy_ref == "operation-policy-inference"
    assert client.authority.model_account_ref == "model-account-inference"
    assert client.authority.service_principal_ref == "service-principal-inference"

    assert {:ok, response} = Inference.complete(client, "hello")
    assert response.trace.metadata.authority_ref == "auth-inference"
    assert response.trace.metadata.endpoint_ref == "endpoint-inference"

    assert response.trace.metadata.authority_refs.credential_handle_ref ==
             "credential-handle-inference"

    assert response.trace.metadata.authority_refs.operation_policy_ref ==
             "operation-policy-inference"
  end

  test "governed client requires inference-family lease attach and operation refs" do
    required_refs = [
      :credential_handle_ref,
      :credential_lease_ref,
      :target_posture_ref,
      :attach_grant_ref,
      :operation_policy_ref,
      :model_account_ref,
      :service_principal_ref
    ]

    for ref <- required_refs do
      assert {:error, %Error{category: :invalid, reason: :governed_authority} = error} =
               Client.new(governed_authority: Map.delete(authority(), ref))

      assert ref in error.metadata.fields
    end
  end

  test "governed ASM adapter handoff carries runtime authority refs only" do
    assert {:ok, client} =
             Client.new(
               governed_authority:
                 authority(
                   adapter_ref: "asm",
                   provider_ref: "codex",
                   model: "codex-governed",
                   adapter_opts: [
                     asm_module: FakeASM,
                     asm_options_module: FakeASMOptions
                   ]
                 )
             )

    assert {:ok, response} = Inference.complete(client, "hello")
    assert response.metadata.opts[:runtime_auth_mode] == :governed
    assert response.metadata.opts[:runtime_auth_scope] == :governed
    assert response.metadata.opts[:authority_ref] == "auth-inference"
    assert response.metadata.opts[:execution_context_ref] == "execution-inference"
    assert response.metadata.opts[:connector_instance_ref] == "connector-instance-inference"
    assert response.metadata.opts[:connector_binding_ref] == "connector-binding-inference"
    assert response.metadata.opts[:provider_account_ref] == "provider-account-inference"
    assert response.metadata.opts[:credential_lease_ref] == "credential-lease-inference"
    assert response.metadata.opts[:native_auth_assertion_ref] == "native-auth-inference"
    assert response.metadata.opts[:target_ref] == "target-inference"
    assert response.metadata.opts[:operation_policy_ref] == "operation-policy-inference"
    refute inspect(response.metadata.opts) =~ "secret-value"
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
      connector_instance_ref: "connector-instance-inference",
      connector_binding_ref: "connector-binding-inference",
      endpoint_ref: "endpoint-inference",
      provider_account_ref: "provider-account-inference",
      credential_ref: "credential-inference",
      credential_handle_ref: "credential-handle-inference",
      credential_lease_ref: "credential-lease-inference",
      target_ref: "target-inference",
      target_posture_ref: "target-posture-inference",
      attach_grant_ref: "attach-grant-inference",
      operation_policy_ref: "operation-policy-inference",
      model_ref: "model-inference",
      model_account_ref: "model-account-inference",
      service_identity_ref: "service-inference",
      service_principal_ref: "service-principal-inference",
      native_auth_assertion_ref: "native-auth-inference",
      model: "governed-model",
      adapter_opts: [response_text: "governed-ok"],
      redaction_values: ["secret-value"]
    }
    |> Map.merge(Map.new(overrides))
  end
end
