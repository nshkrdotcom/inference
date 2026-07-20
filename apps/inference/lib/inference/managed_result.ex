defmodule Inference.ManagedResult do
  @moduledoc false

  alias Inference.{Client, Error, GovernedAuthority, Redaction, Response, StreamEvent}

  @error_categories [
    :invalid,
    :missing_dependency,
    :missing_credentials,
    :timeout,
    :rate_limited,
    :invalid_response,
    :unsupported_capability,
    :adapter_exception,
    :provider_error
  ]

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
        _implementation -> {:ok, managed_stream(stream)}
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
    Error.new(
      safe_error_category(error.category),
      safe_error_reason(error.reason),
      safe_error_message(error),
      %{details_redacted?: true}
    )
  end

  defp safe_error_category(category) when category in @error_categories, do: category
  defp safe_error_category(_category), do: :provider_error

  defp safe_error_reason(reason) when is_atom(reason), do: reason
  defp safe_error_reason(_reason), do: :managed_adapter_error

  defp safe_error_message(%Error{reason: :adapter_exception}),
    do: "managed adapter raised; exception details were redacted"

  defp safe_error_message(%Error{}),
    do: "managed adapter error; provider details were redacted"

  defp managed_stream(stream) do
    Stream.resource(
      fn -> {:enumerable, stream} end,
      &managed_stream_next/1,
      &managed_stream_after/1
    )
  end

  defp managed_stream_next(:done), do: {:halt, :done}

  defp managed_stream_next(state) do
    case safe_reduce_one(state) do
      {:ok, {:suspended, event, continuation}} ->
        case safe_sanitize_event(event) do
          {:ok, sanitized} ->
            {[sanitized], {:continuation, continuation}}

          :error ->
            halt_continuation(continuation)
            {[stream_failure_event(:invalid_stream_event)], :done}
        end

      {:ok, {:done, _acc}} ->
        {:halt, :done}

      {:ok, {:halted, _acc}} ->
        {:halt, :done}

      {:ok, _invalid_result} ->
        {[stream_failure_event(:invalid_stream_result)], :done}

      :error ->
        {[stream_failure_event(:stream_exception)], :done}
    end
  end

  defp managed_stream_after({:continuation, continuation}) do
    halt_continuation(continuation)
  end

  defp managed_stream_after(_state), do: :ok

  defp safe_reduce_one(state) do
    {:ok, reduce_one(state)}
  rescue
    _exception -> :error
  catch
    _kind, _reason -> :error
  end

  defp reduce_one({:enumerable, enumerable}) do
    Enumerable.reduce(enumerable, {:cont, nil}, fn event, _acc -> {:suspend, event} end)
  end

  defp reduce_one({:continuation, continuation}), do: continuation.({:cont, nil})

  defp safe_sanitize_event(event) do
    {:ok, sanitize_event(event)}
  rescue
    _exception -> :error
  catch
    _kind, _reason -> :error
  end

  defp halt_continuation(continuation) do
    continuation.({:halt, nil})
    :ok
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp stream_failure_event(reason) do
    %StreamEvent{
      type: :error,
      data:
        Error.new(
          :adapter_exception,
          reason,
          "managed stream failed; provider details were redacted",
          %{details_redacted?: true}
        ),
      metadata: %{}
    }
  end

  defp sanitize_event(%StreamEvent{} = event) do
    attrs =
      event
      |> Map.from_struct()
      |> Redaction.redact()

    attrs =
      case event.data do
        %Error{} = error -> Map.put(attrs, :data, sanitize_error(error))
        _other -> attrs
      end

    struct(StreamEvent, attrs)
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
