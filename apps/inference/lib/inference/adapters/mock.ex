defmodule Inference.Adapters.Mock do
  @moduledoc """
  Deterministic adapter for tests and examples.
  """

  @behaviour Inference.Adapter

  alias Inference.{Client, Error, Request, Response, StreamEvent, Trace}

  @impl true
  def complete(%Client{} = client, %Request{} = request) do
    case Keyword.get(client.adapter_opts, :error) do
      nil -> {:ok, response(client, request)}
      %Error{} = error -> {:error, error}
      reason -> {:error, Error.provider_error(reason, adapter: __MODULE__)}
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
