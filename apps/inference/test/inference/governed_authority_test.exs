defmodule Inference.GovernedAuthorityTest do
  use ExUnit.Case, async: true

  alias Inference.{Client, Error, Response, StreamEvent, Trace}

  @sentinel "managed-secret-sentinel"

  defmodule ManagedAdapter do
    @behaviour Inference.Adapter

    alias Inference.{Error, Response, StreamEvent, Trace}

    @sentinel "managed-secret-sentinel"

    @impl true
    def provider_kind, do: :model_endpoint

    @impl true
    def credential_mode, do: :managed_materialization

    @impl true
    def complete(client, request) do
      send(self(), {:managed_complete, client.authority, request})

      cond do
        request.metadata[:raise?] ->
          raise "adapter crash #{@sentinel}"

        request.metadata[:return_error?] ->
          {:error,
           Error.provider_error(:sentinel_failure,
             authorization: @sentinel,
             detail: "provider rejected #{@sentinel}"
           )}

        request.metadata[:return_message_only_error?] ->
          {:error,
           Error.provider_error(@sentinel,
             detail: "provider rejected #{@sentinel}"
           )}

        request.metadata[:return_untyped?] ->
          {:ok, %{provider_payload: @sentinel}}

        true ->
          {:ok,
           Response.new(
             provider: client.provider,
             model: client.model,
             text: "managed answer #{@sentinel}",
             raw: %{api_key: @sentinel, provider_payload: "contains #{@sentinel}"},
             metadata: %{
               authority_ref: client.authority.authority_ref,
               credential_lease_ref: client.authority.credential_lease_ref,
               token: @sentinel,
               note: "used #{@sentinel}"
             },
             trace:
               Trace.new(
                 adapter: __MODULE__,
                 provider: client.provider,
                 metadata: %{authorization: "Bearer #{@sentinel}"}
               )
           )}
      end
    end

    @impl true
    def stream(client, request) do
      send(self(), {:managed_stream, client.authority, request})

      if request.metadata[:raise_during_stream?] do
        {:ok,
         Stream.concat(
           [%StreamEvent{type: :delta, data: "first", metadata: %{}}],
           Stream.map([:raise], fn _event -> raise "stream crash #{@sentinel}" end)
         )}
      else
        {:ok,
         [
           %StreamEvent{
             type: :delta,
             data: "first #{@sentinel}",
             metadata: %{api_key: @sentinel}
           },
           %StreamEvent{type: :delta, data: "second", metadata: %{}},
           %StreamEvent{type: :done, data: nil, metadata: %{}}
         ]}
      end
    end
  end

  test "governed client rejects direct provider authority fields" do
    direct_fields = [
      adapter: Inference.Adapters.Mock,
      provider: :gemini,
      model: "direct-model",
      backend: :direct_backend,
      defaults: [api_key: "direct-key"],
      adapter_opts: [api_key: "direct-key"],
      managed_adapter_opts: [api_key: "direct-key"],
      api_key: "direct-key",
      provider_key: "direct-key",
      endpoint_auth: "direct-endpoint-key",
      service_identity: "direct-service",
      model_account: "direct-model-account",
      env: fn _key -> "direct-key" end
    ]

    for {field, value} <- direct_fields do
      assert {:error, %Error{category: :invalid, reason: :governed_authority} = error} =
               Client.new([
                 {:governed_authority, authority()},
                 {:managed_adapter, ManagedAdapter},
                 {field, value}
               ])

      assert String.contains?(error.message, "direct governed client field")
      assert field in error.metadata.fields
    end
  end

  test "governed reference-only clients fail closed without a materializing adapter" do
    assert {:error,
            %Error{
              category: :missing_credentials,
              reason: :credential_materialization_required
            } = error} = Client.new(governed_authority: authority())

    assert error.message =~ "injected managed-materialization adapter"
  end

  test "direct adapters cannot be injected as managed materializers" do
    assert {:error, %Error{category: :invalid, reason: :managed_adapter} = error} =
             Client.new(
               governed_authority: authority(),
               managed_adapter: Inference.Adapters.Mock
             )

    assert error.metadata.credential_mode == :explicit
  end

  test "governed client selects only the separately injected managed adapter" do
    assert {:ok, client} =
             Client.new(governed_authority: authority(), managed_adapter: ManagedAdapter)

    assert client.adapter == ManagedAdapter
    assert client.provider == :gemini
    assert client.model == "gemini-2.5-flash"
    assert client.defaults == []
    assert client.adapter_opts == []
    assert client.authority.adapter_ref == "gemini_ex"
    assert client.authority.authority_ref == "auth-inference"
    assert client.authority.credential_ref == "credential-inference"
    assert client.authority.credential_handle_ref == "credential-handle-inference"
    assert client.authority.credential_lease_ref == "credential-lease-inference"
    assert client.authority.target_posture_ref == "target-posture-inference"
    assert client.authority.attach_grant_ref == "attach-grant-inference"
    assert client.authority.operation_policy_ref == "operation-policy-inference"
    assert client.authority.model_account_ref == "model-account-inference"
    assert client.authority.service_principal_ref == "service-principal-inference"
  end

  test "governed completion preserves semantic output and removes durable raw material" do
    client = governed_client()

    assert {:ok, %Response{} = response} = Inference.complete(client, "hello")
    assert response.text == "managed answer [REDACTED]"
    assert response.raw == nil
    assert response.metadata.authority_ref == "auth-inference"
    assert response.metadata.credential_lease_ref == "credential-lease-inference"
    assert response.metadata.token == "[REDACTED]"
    assert response.metadata.note == "used [REDACTED]"
    assert response.trace.metadata.authorization == "[REDACTED]"
    refute inspect(response) =~ @sentinel

    assert_received {:managed_complete, authority, request}
    assert authority.adapter_ref == "gemini_ex"
    assert request.messages != []
  end

  test "governed stream preserves real incremental boundaries while sanitizing each event" do
    client = governed_client()

    assert {:ok, stream} = Inference.stream(client, "hello")

    assert [
             %StreamEvent{type: :delta, data: "first [REDACTED]"} = first,
             %StreamEvent{type: :delta, data: "second"},
             %StreamEvent{type: :done}
           ] = Enum.to_list(stream)

    assert first.metadata.api_key == "[REDACTED]"
    refute inspect(first) =~ @sentinel
    assert_received {:managed_stream, authority, _request}
    assert authority.credential_lease_ref == "credential-lease-inference"
  end

  test "governed provider errors are recursively sanitized" do
    client = governed_client()

    assert {:error, %Error{} = error} =
             Inference.complete(client, "hello", metadata: %{return_error?: true})

    assert error.category == :provider_error
    assert error.reason == :sentinel_failure
    assert error.message == "managed adapter error; provider details were redacted"
    assert error.metadata == %{details_redacted?: true}
    refute inspect(error) =~ @sentinel
  end

  test "governed typed errors discard secret-bearing messages and unkeyed details" do
    client = governed_client()

    assert {:error, %Error{} = error} =
             Inference.complete(client, "hello", metadata: %{return_message_only_error?: true})

    assert error.category == :provider_error
    assert error.reason == :provider_error
    assert error.message == "managed adapter error; provider details were redacted"
    assert error.metadata == %{details_redacted?: true}
    refute inspect(error) =~ @sentinel
  end

  test "governed completion never returns an untyped provider payload" do
    client = governed_client()

    assert {:error, %Error{category: :invalid_response, reason: :invalid_managed_result} = error} =
             Inference.complete(client, "hello", metadata: %{return_untyped?: true})

    assert error.metadata.result_redacted?
    refute inspect(error) =~ @sentinel
  end

  test "governed adapter exceptions never preserve provider exception text" do
    client = governed_client()

    assert {:error, %Error{category: :adapter_exception} = error} =
             Inference.complete(client, "hello", metadata: %{raise?: true})

    assert error.message == "managed adapter raised; exception details were redacted"
    assert error.metadata == %{details_redacted?: true}
    refute inspect(error) =~ @sentinel
  end

  test "governed lazy stream exceptions become sanitized terminal error events" do
    client = governed_client()

    assert {:ok, stream} =
             Inference.stream(client, "hello", metadata: %{raise_during_stream?: true})

    events = Enum.to_list(stream)

    assert [
             %StreamEvent{type: :delta, data: "first"},
             %StreamEvent{
               type: :error,
               data: %Error{
                 category: :adapter_exception,
                 reason: :stream_exception,
                 message: "managed stream failed; provider details were redacted",
                 metadata: %{details_redacted?: true}
               }
             }
           ] = events

    refute inspect(events) =~ @sentinel
  end

  test "governed authority rejects materialized or adapter option payloads" do
    unsafe_authorities = [
      Map.put(authority(), :adapter_opts, api_key: @sentinel),
      Map.put(authority(), :defaults, provider_options: %{token: @sentinel}),
      Map.put(authority(), :credential_material, %{api_key: @sentinel}),
      Map.put(authority(), :redaction_values, [@sentinel])
    ]

    for unsafe <- unsafe_authorities do
      assert {:error, %Error{category: :invalid, reason: :governed_authority} = error} =
               Client.new(governed_authority: unsafe, managed_adapter: ManagedAdapter)

      assert error.message =~ "safe references"
      refute inspect(error) =~ @sentinel
    end
  end

  test "governed client and request reject recursively nested raw tokens" do
    assert {:error, %Error{reason: :governed_authority} = client_error} =
             Client.new(
               governed_authority: authority(),
               managed_adapter: ManagedAdapter,
               metadata: %{nested: %{api_key: @sentinel}}
             )

    assert [:metadata, :nested, :api_key] in client_error.metadata.fields
    refute inspect(client_error) =~ @sentinel

    client = governed_client()

    assert {:error, %Error{reason: :governed_request_options} = request_error} =
             Inference.complete(client, "hello",
               options: [provider_options: %{nested: %{access_token: @sentinel}}]
             )

    assert [:options, :provider_options] in request_error.metadata.fields
    refute_received {:managed_complete, _, _}
    refute inspect(request_error) =~ @sentinel
  end

  test "governed completion rejects direct model and routing supplementation" do
    client = governed_client()

    assert {:error, %Error{reason: :governed_request_options} = model_error} =
             Inference.complete(client, "hello", model: "unmanaged-model")

    assert :model in model_error.metadata.fields

    assert {:error, %Error{reason: :governed_request_options} = route_error} =
             Inference.complete(client, "hello", options: [base_url: "https://other.invalid"])

    assert :base_url in route_error.metadata.fields
    refute_received {:managed_complete, _, _}
  end

  test "governed client rejects unknown target adapter and provider refs" do
    assert {:error, %Error{category: :invalid, reason: :governed_authority} = error} =
             Client.new(
               governed_authority: authority(adapter_ref: "unknown-adapter"),
               managed_adapter: ManagedAdapter
             )

    assert error.message == "unknown governed adapter ref"
    assert error.metadata.adapter_ref == "unknown-adapter"

    assert {:error, %Error{category: :invalid, reason: :governed_authority} = error} =
             Client.new(
               governed_authority: authority(provider_ref: "unknown-provider"),
               managed_adapter: ManagedAdapter
             )

    assert error.message == "unknown governed provider ref"
    assert error.metadata.provider_ref == "unknown-provider"
  end

  test "governed client requires endpoint lease attach operation and identity refs" do
    required_refs = [
      :endpoint_ref,
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
               Client.new(
                 governed_authority: Map.delete(authority(), ref),
                 managed_adapter: ManagedAdapter
               )

      assert ref in error.metadata.fields
    end
  end

  test "standalone explicit provider options remain isolated from managed selection" do
    client =
      Client.new!(
        adapter: Inference.Adapters.Mock,
        provider: :mock,
        model: "standalone-model",
        adapter_opts: [response_text: "standalone-ok", api_key: "standalone-explicit-key"]
      )

    assert {:ok, %Response{text: "standalone-ok"}} = Inference.complete(client, "hello")
    refute client.authority
  end

  test "trace redaction preserves opaque refs and removes exact secret values" do
    redacted =
      Trace.redact(%Trace{
        metadata: %{
          credential_lease_ref: "credential-lease-inference",
          note: "using secret-value from endpoint",
          redaction_values: ["secret-value"]
        }
      })

    assert redacted.metadata.credential_lease_ref == "credential-lease-inference"
    assert redacted.metadata.note == "using [REDACTED] from endpoint"
    assert redacted.metadata.redaction_values == ["[REDACTED]"]
  end

  defp governed_client do
    Client.new!(governed_authority: authority(), managed_adapter: ManagedAdapter)
  end

  defp authority(overrides \\ []) do
    %{
      authority_ref: "auth-inference",
      execution_context_ref: "execution-inference",
      adapter_ref: "gemini_ex",
      provider_ref: "gemini",
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
      model: "gemini-2.5-flash"
    }
    |> Map.merge(Map.new(overrides))
  end
end
