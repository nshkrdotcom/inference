defmodule Inference.GovernedAuthority do
  @moduledoc """
  Provider-neutral governed authority envelope checks for shared clients.

  This module validates and carries refs used by governed adapter owners. It
  does not lease credentials, select routes, attach targets, or materialize raw
  provider secrets. Reference-only authority never selects its target adapter
  directly: callers must separately inject a managed-materialization adapter.
  """

  alias Inference.{Adapter, Client, Error, Request}

  @required_refs [
    :authority_ref,
    :execution_context_ref,
    :adapter_ref,
    :provider_ref,
    :connector_instance_ref,
    :connector_binding_ref,
    :endpoint_ref,
    :provider_account_ref,
    :credential_ref,
    :credential_handle_ref,
    :credential_lease_ref,
    :target_ref,
    :target_posture_ref,
    :attach_grant_ref,
    :operation_policy_ref,
    :model_ref,
    :model_account_ref,
    :service_identity_ref,
    :service_principal_ref
  ]

  @optional_refs [
    :native_auth_assertion_ref
  ]

  @ref_fields @required_refs ++ @optional_refs

  @direct_client_fields [
    :adapter,
    :provider,
    :model,
    :backend,
    :defaults,
    :adapter_opts,
    :managed_adapter_opts,
    :api_key,
    :provider_key,
    :endpoint_auth,
    :service_identity,
    :service_principal,
    :model_account,
    :runtime_auth,
    :runtime_auth_mode,
    :runtime_auth_scope,
    :execution_context_ref,
    :connector_instance_ref,
    :connector_binding_ref,
    :provider_account_ref,
    :credential_lease_ref,
    :native_auth_assertion_ref,
    :target_ref,
    :target_posture_ref,
    :attach_grant_ref,
    :operation_policy_ref,
    :env
  ]

  @direct_request_fields [
    :api_key,
    :provider_key,
    :endpoint_auth,
    :service_identity,
    :service_principal,
    :model_account,
    :runtime_auth,
    :runtime_auth_mode,
    :runtime_auth_scope,
    :execution_context_ref,
    :connector_instance_ref,
    :connector_binding_ref,
    :provider_account_ref,
    :credential_lease_ref,
    :native_auth_assertion_ref,
    :target_ref,
    :target_posture_ref,
    :attach_grant_ref,
    :operation_policy_ref,
    :env,
    :credential,
    :authorization,
    :bearer,
    :base_url
  ]

  @adapter_refs ~w[asm gemini_ex mock req_llm reqllm_next]

  @provider_refs %{
    "anthropic" => :anthropic,
    "codex" => :codex,
    "gemini" => :gemini,
    "google" => :google,
    "mock" => :mock,
    "openai" => :openai
  }

  @spec materialize_client_attrs(keyword() | map()) :: {:ok, map()} | {:error, Error.t()}
  def materialize_client_attrs(attrs) when is_list(attrs) do
    attrs
    |> Map.new()
    |> materialize_client_attrs()
  end

  def materialize_client_attrs(attrs) when is_map(attrs) do
    case fetch(attrs, :governed_authority) do
      nil ->
        {:ok, attrs}

      authority ->
        with {:ok, normalized} <- normalize_authority(authority),
             :ok <- reject_direct_client_fields(attrs),
             :ok <- reject_unsafe_authority_fields(normalized),
             :ok <- reject_secret_bearing_metadata(fetch(attrs, :metadata, %{})),
             :ok <- validate_required_refs(normalized),
             :ok <- validate_adapter_ref(normalized),
             {:ok, adapter} <- managed_adapter_for(attrs),
             {:ok, provider} <- provider_for(normalized),
             {:ok, model} <- required_binary(normalized, :model) do
          refs = ref_projection(normalized)

          metadata =
            attrs
            |> fetch(:metadata, %{})
            |> Map.put(:authority_refs, refs)
            |> Map.put(:authority_ref, fetch(normalized, :authority_ref))
            |> Map.put(:endpoint_ref, fetch(normalized, :endpoint_ref))
            |> Map.put(:provider_account_ref, fetch(normalized, :provider_account_ref))
            |> Map.put(:credential_ref, fetch(normalized, :credential_ref))
            |> Map.put(:credential_handle_ref, fetch(normalized, :credential_handle_ref))
            |> Map.put(:credential_lease_ref, fetch(normalized, :credential_lease_ref))
            |> Map.put(:target_ref, fetch(normalized, :target_ref))
            |> Map.put(:target_posture_ref, fetch(normalized, :target_posture_ref))
            |> Map.put(:attach_grant_ref, fetch(normalized, :attach_grant_ref))
            |> Map.put(:operation_policy_ref, fetch(normalized, :operation_policy_ref))
            |> Map.put(:model_account_ref, fetch(normalized, :model_account_ref))
            |> Map.put(:service_identity_ref, fetch(normalized, :service_identity_ref))
            |> Map.put(:service_principal_ref, fetch(normalized, :service_principal_ref))

          {:ok,
           attrs
           |> Map.drop([:governed_authority, :managed_adapter])
           |> Map.merge(%{
             adapter: adapter,
             provider: provider,
             model: model,
             backend: optional_existing(normalized, :backend),
             admitted_kinds: fetch(normalized, :admitted_kinds, fetch(attrs, :admitted_kinds)),
             defaults: [],
             capabilities: fetch(attrs, :capabilities, []),
             metadata: metadata,
             adapter_opts: [],
             authority: authority_metadata(normalized)
           })}
        end
    end
  end

  @spec governed?(Client.t()) :: boolean()
  def governed?(%Client{authority: authority}) when is_map(authority), do: true
  def governed?(%Client{}), do: false

  @spec ref_projection(keyword() | map() | term()) :: map()
  def ref_projection(authority) when is_list(authority) do
    authority
    |> Map.new()
    |> ref_projection()
  end

  def ref_projection(authority) when is_map(authority) do
    @ref_fields
    |> Enum.reduce(%{}, fn field, acc ->
      case fetch(authority, field) do
        value when is_binary(value) and value != "" -> Map.put(acc, field, value)
        _other -> acc
      end
    end)
  end

  def ref_projection(_authority), do: %{}

  @spec reject_direct_request_options(Client.t(), Request.t()) :: :ok | {:error, Error.t()}
  def reject_direct_request_options(%Client{} = client, %Request{} = request) do
    if governed?(client) do
      fields =
        request
        |> direct_request_fields()
        |> Kernel.++(secret_bearing_request_paths(request))
        |> Enum.uniq()

      if fields == [] do
        :ok
      else
        {:error,
         Error.invalid(
           :governed_request_options,
           "direct request fields cannot accompany governed authority",
           fields: fields
         )}
      end
    else
      :ok
    end
  end

  defp direct_request_fields(%Request{} = request) do
    option_hits =
      @direct_request_fields
      |> Enum.filter(&Keyword.has_key?(request.options, &1))

    model_hit = if is_binary(request.model), do: [:model], else: []

    Enum.uniq(model_hit ++ option_hits)
  end

  defp secret_bearing_request_paths(%Request{} = request) do
    [
      options: request.options,
      metadata: request.metadata,
      trace_context: request.trace_context
    ]
    |> Enum.flat_map(fn {root, value} -> secret_bearing_paths(value, [root]) end)
  end

  defp reject_direct_client_fields(attrs) do
    hits =
      @direct_client_fields
      |> Enum.filter(&has_field?(attrs, &1))

    if hits == [] do
      :ok
    else
      {:error,
       Error.invalid(:governed_authority, "direct governed client field is not allowed",
         fields: hits
       )}
    end
  end

  defp reject_unsafe_authority_fields(authority) do
    paths = secret_bearing_paths(authority, [])

    unsafe_fields =
      [:adapter_opts, :defaults, :redaction_values, :managed_adapter, :managed_adapter_opts]
      |> Enum.filter(&has_field?(authority, &1))
      |> Enum.map(&[&1])

    case Enum.uniq(paths ++ unsafe_fields) do
      [] ->
        :ok

      fields ->
        {:error,
         Error.invalid(
           :governed_authority,
           "governed authority must contain safe references, not materialized options",
           fields: fields
         )}
    end
  end

  defp reject_secret_bearing_metadata(metadata) do
    case secret_bearing_paths(metadata, [:metadata]) do
      [] ->
        :ok

      fields ->
        {:error,
         Error.invalid(
           :governed_authority,
           "governed client metadata cannot contain credential material",
           fields: fields
         )}
    end
  end

  defp validate_required_refs(authority) do
    missing =
      @required_refs
      |> Enum.reject(fn key ->
        case fetch(authority, key) do
          value when is_binary(value) -> String.trim(value) != ""
          _other -> false
        end
      end)

    if missing == [] do
      :ok
    else
      {:error,
       Error.invalid(:governed_authority, "governed authority refs are missing", fields: missing)}
    end
  end

  defp validate_adapter_ref(authority) do
    ref = fetch(authority, :adapter_ref)

    if ref in @adapter_refs do
      :ok
    else
      {:error,
       Error.invalid(:governed_authority, "unknown governed adapter ref", adapter_ref: ref)}
    end
  end

  defp managed_adapter_for(attrs) do
    case fetch(attrs, :managed_adapter) do
      nil ->
        {:error,
         Error.new(
           :missing_credentials,
           :credential_materialization_required,
           "governed inference requires an injected managed-materialization adapter"
         )}

      adapter when is_atom(adapter) ->
        validate_managed_adapter(adapter)

      adapter ->
        {:error,
         Error.invalid(:managed_adapter, "managed adapter must be a module atom",
           managed_adapter: adapter
         )}
    end
  end

  defp validate_managed_adapter(adapter) do
    cond do
      not Code.ensure_loaded?(adapter) ->
        {:error, Error.missing_dependency(adapter)}

      Adapter.credential_mode(adapter) != :managed_materialization ->
        {:error,
         Error.invalid(
           :managed_adapter,
           "governed inference adapter must own managed credential materialization",
           managed_adapter: adapter,
           credential_mode: Adapter.credential_mode(adapter)
         )}

      true ->
        {:ok, adapter}
    end
  end

  defp provider_for(authority) do
    ref = fetch(authority, :provider_ref)

    case Map.fetch(@provider_refs, ref) do
      {:ok, provider} ->
        {:ok, provider}

      :error ->
        {:error,
         Error.invalid(:governed_authority, "unknown governed provider ref", provider_ref: ref)}
    end
  end

  defp required_binary(authority, key) do
    case fetch(authority, key) do
      value when is_binary(value) ->
        value = String.trim(value)

        if value == "" do
          {:error, Error.invalid(:governed_authority, "missing governed value", field: key)}
        else
          {:ok, value}
        end

      _other ->
        {:error, Error.invalid(:governed_authority, "missing governed value", field: key)}
    end
  end

  defp authority_metadata(authority) do
    authority
    |> ref_projection()
    |> Map.merge(%{
      authority_ref: fetch(authority, :authority_ref),
      execution_context_ref: fetch(authority, :execution_context_ref),
      adapter_ref: fetch(authority, :adapter_ref),
      provider_ref: fetch(authority, :provider_ref),
      connector_instance_ref: fetch(authority, :connector_instance_ref),
      connector_binding_ref: fetch(authority, :connector_binding_ref),
      endpoint_ref: fetch(authority, :endpoint_ref),
      provider_account_ref: fetch(authority, :provider_account_ref),
      credential_ref: fetch(authority, :credential_ref),
      credential_handle_ref: fetch(authority, :credential_handle_ref),
      credential_lease_ref: fetch(authority, :credential_lease_ref),
      target_ref: fetch(authority, :target_ref),
      target_posture_ref: fetch(authority, :target_posture_ref),
      attach_grant_ref: fetch(authority, :attach_grant_ref),
      operation_policy_ref: fetch(authority, :operation_policy_ref),
      model_ref: fetch(authority, :model_ref),
      model_account_ref: fetch(authority, :model_account_ref),
      service_identity_ref: fetch(authority, :service_identity_ref),
      service_principal_ref: fetch(authority, :service_principal_ref),
      native_auth_assertion_ref: fetch(authority, :native_auth_assertion_ref)
    })
  end

  defp normalize_authority(authority) when is_map(authority), do: {:ok, authority}
  defp normalize_authority(authority) when is_list(authority), do: {:ok, Map.new(authority)}

  defp normalize_authority(_authority) do
    {:error, Error.invalid(:governed_authority, "governed authority must be a map")}
  end

  defp optional_existing(authority, key), do: fetch(authority, key)

  defp secret_bearing_paths(%_struct{} = value, path) do
    value
    |> Map.from_struct()
    |> secret_bearing_paths(path)
  end

  defp secret_bearing_paths(map, path) when is_map(map) do
    Enum.flat_map(map, &secret_bearing_entry_paths(&1, path))
  end

  defp secret_bearing_paths(list, path) when is_list(list) do
    if Keyword.keyword?(list) do
      Enum.flat_map(list, &secret_bearing_entry_paths(&1, path))
    else
      list
      |> Enum.with_index()
      |> Enum.flat_map(fn {value, index} -> secret_bearing_paths(value, path ++ [index]) end)
    end
  end

  defp secret_bearing_paths(_value, _path), do: []

  defp secret_bearing_entry_paths({key, value}, path) do
    child_path = path ++ [key]

    if secret_key?(key) do
      [child_path]
    else
      secret_bearing_paths(value, child_path)
    end
  end

  defp secret_key?(key) do
    normalized = key |> to_string() |> String.downcase()

    not safe_reference_key?(normalized) and
      Enum.any?(
        ~w[
          api_key apikey authorization bearer credential_header credential_material
          credential_payload credential_query password provider_options secret token
        ],
        &String.contains?(normalized, &1)
      )
  end

  defp safe_reference_key?(key) do
    Enum.any?(~w[_ref _refs _id _ids _generation _fence], &String.ends_with?(key, &1))
  end

  defp has_field?(attrs, key), do: Map.has_key?(attrs, key) or Map.has_key?(attrs, to_string(key))

  defp fetch(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key), default)
  end
end
