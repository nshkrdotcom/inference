defmodule Inference.Error do
  @moduledoc """
  Stable error envelope for inference failures.
  """

  defexception [:category, :reason, :message, metadata: %{}]

  @type category ::
          :invalid
          | :missing_dependency
          | :missing_credentials
          | :timeout
          | :rate_limited
          | :invalid_response
          | :unsupported_capability
          | :adapter_exception
          | :provider_error

  @type t :: %__MODULE__{
          category: category(),
          reason: atom(),
          message: String.t(),
          metadata: map()
        }

  @impl Exception
  def message(%__MODULE__{message: message}), do: message

  @spec new(category(), atom(), String.t(), keyword() | map()) :: t()
  def new(category, reason, message, metadata \\ %{}) do
    %__MODULE__{
      category: category,
      reason: reason,
      message: message,
      metadata: normalize_metadata(metadata)
    }
  end

  def invalid(reason, message, metadata \\ []), do: new(:invalid, reason, message, metadata)

  def missing_dependency(module, metadata \\ []) do
    new(:missing_dependency, :missing_dependency, "missing dependency #{inspect(module)}",
      module: module,
      details: metadata
    )
  end

  def missing_credentials(provider, metadata \\ []) do
    new(
      :missing_credentials,
      :missing_credentials,
      "missing credentials for #{inspect(provider)}",
      provider: provider,
      details: metadata
    )
  end

  def unsupported_capability(capability, metadata \\ []) do
    message = Keyword.get(metadata, :message, "unsupported capability #{inspect(capability)}")
    new(:unsupported_capability, :unsupported_capability, message, metadata)
  end

  @doc """
  Reports that an adapter cannot map a declared `Inference.ResponseFormat`.

  Adapters return this instead of silently dropping the declared format.
  """
  @spec response_format_unsupported(term(), keyword()) :: t()
  def response_format_unsupported(response_format, metadata \\ []) do
    message =
      Keyword.get(
        metadata,
        :message,
        "adapter cannot map response_format #{inspect(response_format)}"
      )

    new(
      :unsupported_capability,
      :response_format_unsupported,
      message,
      Keyword.put(metadata, :response_format, response_format)
    )
  end

  @doc """
  Reports a provider-returned tool call on a completion-only adapter.

  A returned tool call is a contract failure. Adapters never execute one.
  """
  @spec unexpected_tool_call(list(), keyword()) :: t()
  def unexpected_tool_call(tool_calls, metadata \\ []) when is_list(tool_calls) do
    new(
      :invalid_response,
      :unexpected_tool_call,
      "completion-only adapter received a provider tool call",
      Keyword.put(metadata, :tool_calls, tool_calls)
    )
  end

  def provider_error(reason, metadata \\ []) do
    new(:provider_error, normalize_reason(reason), "provider error: #{inspect(reason)}", metadata)
  end

  def adapter_exception(exception, metadata \\ []) do
    new(
      :adapter_exception,
      :adapter_exception,
      Exception.message(exception),
      Keyword.merge(metadata, exception: exception.__struct__)
    )
  end

  defp normalize_reason(reason) when is_atom(reason), do: reason
  defp normalize_reason(_reason), do: :provider_error

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(metadata) when is_list(metadata), do: Map.new(metadata)
  defp normalize_metadata(metadata), do: %{details: metadata}
end
