defmodule Gemini.GovernedAuthority do
  @moduledoc false

  @enforce_keys [:refs]
  defstruct [:refs]

  def new!(%__MODULE__{refs: refs} = authority) when is_map(refs), do: authority
  def refs(%__MODULE__{refs: refs}), do: refs
end

defmodule Gemini do
  @moduledoc false

  def configure_test(mode, test_pid) do
    Process.put(:managed_gemini_test_mode, mode)
    Process.put(:managed_gemini_test_pid, test_pid)
    :ok
  end

  def generate(prompt, opts) do
    send(test_pid(), {:gemini_generate, prompt, opts})

    case Process.get(:managed_gemini_test_mode) do
      :unary ->
        {:ok,
         %{
           "responseId" => "response-1",
           "modelVersion" => "gemini-2.5-flash",
           "candidates" => [
             %{
               "content" => %{"parts" => [%{"text" => "governed reply"}]},
               "finishReason" => "STOP"
             }
           ],
           "usageMetadata" => %{
             "promptTokenCount" => 3,
             "candidatesTokenCount" => 2,
             "totalTokenCount" => 5
           }
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def start_stream(prompt, opts) do
    with :ok <- validate_stream_opts(prompt, opts) do
      stream_id = "stream-#{System.unique_integer([:positive])}"

      Process.put(
        {:managed_gemini_stream_mode, stream_id},
        Process.get(:managed_gemini_test_mode)
      )

      {:ok, stream_id}
    end
  end

  def subscribe_stream(stream_id) do
    target = self()
    mode = Process.get({:managed_gemini_stream_mode, stream_id})

    sender =
      spawn(fn ->
        emit_stream(mode, target, stream_id)
      end)

    Process.put({:managed_gemini_stream_sender, stream_id}, sender)
    :ok
  end

  def stop_stream(stream_id) do
    case Process.get({:managed_gemini_stream_sender, stream_id}) do
      pid when is_pid(pid) -> Process.exit(pid, :kill)
      _other -> :ok
    end

    send(test_pid(), {:gemini_stopped, stream_id})
    :ok
  end

  defp emit_stream(:ordered_stream, target, stream_id) do
    send(target, {
      :stream_event,
      stream_id,
      %{
        type: :data,
        data: %{
          "candidates" => [%{"content" => %{"parts" => [%{"text" => "first"}]}}]
        }
      }
    })

    send(target, {
      :stream_event,
      stream_id,
      %{
        type: :data,
        data: %{
          "usageMetadata" => %{
            "promptTokenCount" => 1,
            "candidatesTokenCount" => 2,
            "totalTokenCount" => 3
          }
        }
      }
    })

    send(target, {
      :stream_event,
      stream_id,
      %{
        type: :data,
        data: %{
          "candidates" => [
            %{
              "content" => %{"parts" => [%{"text" => "second"}]},
              "finishReason" => "STOP"
            }
          ]
        }
      }
    })

    send(target, {:stream_complete, stream_id})
  end

  defp emit_stream(:cancellable_stream, target, stream_id) do
    send(target, {
      :stream_event,
      stream_id,
      %{
        type: :data,
        data: %{"candidates" => [%{"content" => %{"parts" => [%{"text" => "first"}]}}]}
      }
    })

    Process.sleep(:infinity)
  end

  defp emit_stream(:provider_error, target, stream_id) do
    send(target, {
      :stream_event,
      stream_id,
      %{type: :error, data: nil, error: {:provider_failed, "managed-stream-secret"}}
    })

    send(target, {:stream_error, stream_id, {:provider_failed, "managed-stream-secret"}})
  end

  defp emit_stream(:provider_cancelled, target, stream_id) do
    send(target, {:stream_cancelled, stream_id})
  end

  defp validate_stream_opts(prompt, opts) do
    mode = Process.get(:managed_gemini_test_mode)

    if prompt == "hello" and opts[:model] == "gemini-2.5-flash" and opts[:max_retries] == 0 and
         is_struct(opts[:governed_authority], Gemini.GovernedAuthority) and
         (mode != :ordered_stream or opts[:temperature] == 0.2) do
      :ok
    else
      {:error, :invalid_test_stream_options}
    end
  end

  defp test_pid do
    case Process.get(:managed_gemini_test_pid) do
      pid when is_pid(pid) -> pid
      _other -> raise "managed Gemini test process is not configured"
    end
  end
end

defmodule Inference.Adapters.GeminiExManagedTest do
  use ExUnit.Case, async: false

  alias Inference.Adapters.GeminiExManaged
  alias Inference.{Client, Error, Response, StreamEvent}

  @model "gemini-2.5-flash"

  setup do
    Gemini.configure_test(:unary, self())
    :ok
  end

  test "reports the managed semantic provider boundary" do
    assert GeminiExManaged.provider_kind() == :model_endpoint
    assert GeminiExManaged.credential_mode() == :managed_materialization
  end

  test "forwards governed unary generation and preserves usage and terminal fields" do
    client = client()

    assert {:ok,
            %Response{
              provider: :gemini,
              model: @model,
              text: "governed reply",
              usage: %{input_tokens: 3, output_tokens: 2, total_tokens: 5},
              finish_reason: "STOP",
              raw: nil
            } = response} = Inference.complete(client, "hello", max_tokens: 64)

    assert response.metadata.managed_authority_refs.provider_account_ref ==
             "account://google/gemini/a"

    assert_received {:gemini_generate, "hello", opts}
    assert opts[:model] == @model
    assert opts[:max_output_tokens] == 64
    assert opts[:max_retries] == 0
    assert %Gemini.GovernedAuthority{refs: refs} = opts[:governed_authority]
    assert refs.provider_account_ref == "account://google/gemini/a"
    refute Keyword.has_key?(opts, :api_key)
    refute Keyword.has_key?(opts, :auth)
    refute Keyword.has_key?(opts, :base_url)
  end

  test "forwards provider delta boundaries, usage, and terminal state in order" do
    Gemini.configure_test(:ordered_stream, self())

    assert {:ok, stream} = Inference.stream(client(), "hello", temperature: 0.2)

    assert [
             %StreamEvent{type: :delta, data: "first"},
             %StreamEvent{
               type: :usage,
               data: %{input_tokens: 1, output_tokens: 2, total_tokens: 3}
             },
             %StreamEvent{type: :delta, data: "second"},
             %StreamEvent{
               type: :done,
               data: %{
                 finish_reason: "STOP",
                 usage: %{input_tokens: 1, output_tokens: 2, total_tokens: 3}
               }
             }
           ] = Enum.to_list(stream)
  end

  test "halts the real provider stream when the inference consumer cancels" do
    Gemini.configure_test(:cancellable_stream, self())

    assert {:ok, stream} = Inference.stream(client(), "hello")
    assert [%StreamEvent{type: :delta, data: "first"}] = Enum.take(stream, 1)

    assert_received {:gemini_stopped, stream_id}
    assert is_binary(stream_id)
  end

  test "preserves provider error and cancellation as distinct terminal events" do
    Gemini.configure_test(:provider_error, self())
    assert {:ok, failed_stream} = Inference.stream(client(), "hello")

    failed_events = Enum.to_list(failed_stream)

    assert [
             %StreamEvent{
               type: :error,
               data: %Error{category: :provider_error, reason: :provider_failed}
             }
           ] = failed_events

    refute inspect(failed_events) =~ "managed-stream-secret"

    Gemini.configure_test(:provider_cancelled, self())
    assert {:ok, cancelled_stream} = Inference.stream(client(), "hello")
    assert [%StreamEvent{type: :cancelled, data: nil}] = Enum.to_list(cancelled_stream)
  end

  test "rejects authority, model, and adapter option mismatches before provider dispatch" do
    mismatched_authority = Map.put(client_authority(), :provider_account_ref, "account://other")

    assert {:error, %Error{reason: :managed_authority_mismatch}} =
             Inference.complete(client(authority: mismatched_authority), "hello")

    assert {:error, %Error{reason: :managed_gemini_model_mismatch}} =
             Inference.complete(client(), "hello", options: [model: "gemini-other"])

    assert {:error, %Error{reason: :credential_materialization_required}} =
             Inference.complete(
               client(adapter_opts: [governed_authority: authority(), gemini_module: Gemini]),
               "hello"
             )

    refute_received {:gemini_generate, _, _}
  end

  test "rejects global, credential, routing, and callback supplementation" do
    facade_forbidden = [
      api_key: "managed-sentinel",
      base_url: "https://other.invalid"
    ]

    adapter_forbidden = [
      auth: :gemini,
      gemini_module: OtherGemini,
      callback: &Function.identity/1
    ]

    for {field, value} <- facade_forbidden do
      assert {:error, %Error{reason: :governed_request_options}} =
               Inference.complete(client(), "hello", options: [{field, value}])
    end

    for {field, value} <- adapter_forbidden do
      assert {:error, %Error{reason: :managed_gemini_options}} =
               Inference.complete(client(), "hello", options: [{field, value}])
    end

    refute_received {:gemini_generate, _, _}
  end

  defp client(overrides \\ []) do
    governed_authority = authority()

    attrs = [
      adapter: GeminiExManaged,
      provider: :gemini,
      model: @model,
      authority: client_authority(governed_authority.refs),
      adapter_opts: [governed_authority: governed_authority]
    ]

    Client.new!(Keyword.merge(attrs, overrides))
  end

  defp authority do
    %Gemini.GovernedAuthority{refs: provider_refs()}
  end

  defp client_authority(provider_refs \\ provider_refs()) do
    Map.merge(
      %{
        execution_context_ref: "execution-context://turn/1",
        adapter_ref: "gemini_ex",
        connector_instance_ref: "connector://gemini/a",
        connector_binding_ref: "binding://gemini/a",
        credential_ref: "credential://gemini/a",
        target_posture_ref: "target-posture://local",
        attach_grant_ref: "grant://gemini/a",
        model_ref: @model,
        service_identity_ref: "service://synapse",
        service_principal_ref: "principal://synapse"
      },
      provider_refs
    )
  end

  defp provider_refs do
    %{
      authority_ref: "authority://gemini/a",
      provider_ref: "provider://google/gemini",
      provider_family: "google_gemini",
      provider_account_ref: "account://google/gemini/a",
      model_account_ref: "account://google/gemini/a",
      tenant_id: "tenant://synapse/a",
      connection_id: "connection://gemini/a",
      endpoint_ref: "endpoint://google/gemini/v1",
      quota_scope_ref: "quota://google/project/a",
      credential_handle_ref: "credential-handle://gemini/a",
      credential_lease_ref: "credential-lease://gemini/a/1",
      materialization_ref: "materialization://gemini/a/1",
      effect_ref: "effect://gemini/a/1",
      operation_ref: "operation://gemini/a/1",
      target_ref: "target://local/http",
      operation_policy_ref: "policy://gemini/model-turn",
      generation: 1,
      fence: 3,
      expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
    }
  end
end
