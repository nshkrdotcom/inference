defmodule Inference.ManagedResult do
  @moduledoc false

  alias Inference.{Client, Error, GovernedAuthority, Redaction, Response, StreamEvent}

  @spec sanitize(term(), Client.t()) :: term()
  def sanitize(result, %Client{} = client) do
    if GovernedAuthority.governed?(client) do
      sanitize_managed(result)
    else
      result
    end
  end

  @spec sanitize_stream(term(), Client.t()) :: term()
  def sanitize_stream({:ok, stream}, %Client{} = client) do
    if GovernedAuthority.governed?(client) do
      case Enumerable.impl_for(stream) do
        nil -> {:error, invalid_managed_result(:stream)}
        _implementation -> {:ok, Stream.map(stream, &sanitize_event/1)}
      end
    else
      {:ok, stream}
    end
  end

  def sanitize_stream(result, %Client{} = client), do: sanitize(result, client)

  defp sanitize_managed({:ok, %Response{} = response}),
    do: {:ok, sanitize_response(response)}

  defp sanitize_managed({:error, %Error{} = error}),
    do: {:error, sanitize_error(error)}

  defp sanitize_managed({:ok, _result}), do: {:error, invalid_managed_result(:completion)}

  defp sanitize_managed({:error, _reason}),
    do: {:error, invalid_managed_error()}

  defp sanitize_managed(_result), do: {:error, invalid_managed_result(:completion)}

  defp sanitize_response(%Response{} = response) do
    attrs = response |> Map.from_struct() |> Redaction.redact()
    struct(Response, Map.put(attrs, :raw, nil))
  end

  defp sanitize_error(%Error{} = error) do
    attrs = error |> Map.from_struct() |> Redaction.redact()

    attrs =
      if error.reason == :adapter_exception do
        Map.put(attrs, :message, "managed adapter raised; exception details were redacted")
      else
        attrs
      end

    struct(Error, attrs)
  end

  defp sanitize_event(%StreamEvent{} = event) do
    event
    |> Map.from_struct()
    |> Redaction.redact()
    |> then(&struct(StreamEvent, &1))
  end

  defp sanitize_event(%Error{} = error), do: sanitize_error(error)

  defp sanitize_event(_event) do
    %StreamEvent{type: :error, data: invalid_managed_result(:stream_event), metadata: %{}}
  end

  defp invalid_managed_result(kind) do
    Error.new(
      :invalid_response,
      :invalid_managed_result,
      "managed adapter returned an invalid #{kind} result",
      %{result_redacted?: true}
    )
  end

  defp invalid_managed_error do
    Error.new(
      :provider_error,
      :managed_adapter_error,
      "managed adapter returned an untyped provider error",
      %{cause_redacted?: true}
    )
  end
end
