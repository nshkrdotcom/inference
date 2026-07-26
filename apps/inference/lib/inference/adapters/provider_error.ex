defmodule Inference.Adapters.ProviderError do
  @moduledoc false

  # Maps provider error structs onto `Inference.Error`'s declared categories.
  #
  # This package declares no provider dependency, so provider error structs are
  # matched STRUCTURALLY by module name and read field by field. The provider's
  # own error value is always preserved under `metadata.provider_error`; the
  # mapping never invents a cause it cannot read.

  alias Inference.Error

  @asm_error ASM.Error
  @gemini_error Gemini.Error

  # ASM.Error kind -> Inference.Error category
  # (/home/home/p/g/n/agent_session_manager/lib/asm/error.ex)
  @asm_categories %{
    timeout: :timeout,
    rate_limit: :rate_limited,
    auth_error: :missing_credentials,
    cli_not_found: :missing_dependency,
    config_invalid: :invalid,
    parse_error: :invalid_response,
    json_decode_error: :invalid_response
  }

  # Gemini.Error type -> Inference.Error category
  # (/home/home/p/g/n/gemini_ex/lib/gemini/error.ex)
  @gemini_categories %{
    auth_error: :missing_credentials,
    config_error: :invalid,
    validation_error: :invalid,
    serialization_error: :invalid_response,
    invalid_response: :invalid_response
  }

  @gemini_status_categories %{
    401 => :missing_credentials,
    403 => :missing_credentials,
    408 => :timeout,
    429 => :rate_limited,
    499 => :timeout,
    504 => :timeout
  }

  @spec normalize(term(), keyword()) :: Error.t()
  def normalize(%Error{} = error, _metadata), do: error

  def normalize(%{__struct__: @asm_error} = reason, metadata), do: asm_error(reason, metadata)

  def normalize(%{__struct__: @gemini_error} = reason, metadata),
    do: gemini_error(reason, metadata)

  def normalize(%{__struct__: _module} = reason, metadata) do
    Error.new(
      :provider_error,
      :provider_error,
      "provider error: #{message_of(reason)}",
      provider_metadata(reason, metadata)
    )
  end

  def normalize(reason, metadata), do: Error.provider_error(reason, metadata)

  defp asm_error(reason, metadata) do
    kind = Map.get(reason, :kind)
    domain = Map.get(reason, :domain)

    metadata =
      reason
      |> provider_metadata(metadata)
      |> Keyword.merge(
        provider_error_kind: kind,
        provider_error_domain: domain,
        provider_retryable: Map.get(reason, :retryable)
      )
      |> maybe_put(:provider, Map.get(reason, :provider))
      |> maybe_put(:provider_exit_code, Map.get(reason, :exit_code))

    Error.new(asm_category(kind), reason_atom(kind), message_of(reason), metadata)
  end

  defp asm_category(kind), do: Map.get(@asm_categories, kind, :provider_error)

  defp gemini_error(reason, metadata) do
    type = Map.get(reason, :type)
    http_status = Map.get(reason, :http_status)

    metadata =
      reason
      |> provider_metadata(metadata)
      |> Keyword.put(:provider_error_type, type)
      |> maybe_put(:provider_http_status, http_status)
      |> maybe_put(:provider_api_reason, Map.get(reason, :api_reason))

    Error.new(gemini_category(type, http_status), reason_atom(type), message_of(reason), metadata)
  end

  defp gemini_category(type, http_status) do
    cond do
      category = Map.get(@gemini_status_categories, http_status) -> category
      category = Map.get(@gemini_categories, type) -> category
      is_integer(http_status) and http_status >= 400 and http_status < 500 -> :invalid
      true -> :provider_error
    end
  end

  defp provider_metadata(reason, metadata) do
    metadata
    |> Keyword.new()
    |> Keyword.put(:provider_error, reason)
  end

  defp reason_atom(reason) when is_atom(reason) and not is_nil(reason), do: reason
  defp reason_atom(_reason), do: :provider_error

  defp message_of(%{message: message}) when is_binary(message), do: message
  defp message_of(reason), do: inspect(reason)

  defp maybe_put(metadata, _key, nil), do: metadata
  defp maybe_put(metadata, key, value), do: Keyword.put(metadata, key, value)
end
