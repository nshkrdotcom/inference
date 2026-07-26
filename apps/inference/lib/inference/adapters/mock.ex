defmodule Inference.Adapters.Mock do
  @moduledoc """
  Deterministic adapter for tests and examples.
  """

  @behaviour Inference.Adapter

  alias Inference.{Client, Error, Request, Response, StreamEvent, Trace}

  @impl true
  def provider_kind, do: :model_endpoint

  @impl true
  def complete(%Client{} = client, %Request{} = request) do
    with :ok <- honors_response_format(client, request) do
      case Keyword.get(client.adapter_opts, :error) do
        nil -> {:ok, response(client, request)}
        %Error{} = error -> {:error, error}
        reason -> {:error, Error.provider_error(reason, adapter: __MODULE__)}
      end
    end
  end

  @impl true
  def stream(%Client{} = client, %Request{} = request) do
    {:ok,
     [
       %StreamEvent{type: :delta, data: Response.text(response(client, request))},
       %StreamEvent{type: :done, data: nil}
     ]}
  end

  # The mock honors a declared JSON format only when the test explicitly
  # configured an object to return. It never fabricates structured output to
  # make a declared format look satisfied.
  defp honors_response_format(%Client{} = client, %Request{} = request) do
    cond do
      request.response_format in [nil, :text] ->
        :ok

      Keyword.has_key?(client.adapter_opts, :response_object) ->
        :ok

      true ->
        {:error,
         Error.response_format_unsupported(request.response_format,
           adapter: __MODULE__,
           message: "configure :response_object to exercise a JSON response format"
         )}
    end
  end

  defp mock_object(%Client{} = client, %Request{} = request) do
    if request.response_format in [nil, :text] do
      nil
    else
      Keyword.get(client.adapter_opts, :response_object)
    end
  end

  defp response(%Client{} = client, %Request{} = request) do
    text =
      Keyword.get_lazy(client.adapter_opts, :response_text, fn ->
        "mock response for: #{Request.user_prompt(request)}"
      end)

    usage = %{
      input_tokens: String.length(Request.to_prompt(request)),
      output_tokens: String.length(text)
    }

    metadata = Map.merge(client.metadata, request.metadata)

    Response.new(
      id: request.id || "mock-response",
      provider: client.provider || :mock,
      model: request.model || client.model || "mock",
      text: text,
      object: mock_object(client, request),
      usage: usage,
      finish_reason: :stop,
      metadata: metadata,
      trace:
        Trace.new(
          adapter: __MODULE__,
          provider: client.provider || :mock,
          model: request.model || client.model || "mock",
          backend: client.backend || :mock,
          usage: usage,
          finish_reason: :stop,
          metadata: metadata
        )
    )
  end
end
