defmodule Inference.Adapters.Shared do
  @moduledoc false

  alias Inference.{Client, Error, Request, Response, Trace}

  @spec ensure_dependency(module()) :: :ok | {:error, Error.t()}
  def ensure_dependency(module) do
    if Code.ensure_loaded?(module) do
      :ok
    else
      {:error, Error.missing_dependency(module)}
    end
  end

  @spec request_opts(Client.t(), Request.t()) :: keyword()
  def request_opts(%Client{} = client, %Request{} = request) do
    client.defaults
    |> Keyword.merge(request.options)
    |> maybe_put(:model, request.model || client.model)
    |> maybe_put(:temperature, request.temperature)
    |> maybe_put(:top_p, request.top_p)
    |> maybe_put(:max_tokens, request.max_tokens)
    |> maybe_put(:response_format, request.response_format)
  end

  @spec response_from_result(term(), Client.t(), Request.t(), keyword()) :: Response.t()
  def response_from_result(result, %Client{} = client, %Request{} = request, opts \\ []) do
    text = Keyword.get_lazy(opts, :text, fn -> extract_text(result) end)
    usage = Keyword.get_lazy(opts, :usage, fn -> extract_field(result, :usage) end)

    finish_reason =
      Keyword.get_lazy(opts, :finish_reason, fn -> extract_field(result, :finish_reason) end)

    metadata = Keyword.get(opts, :metadata, %{})
    object = Keyword.get_lazy(opts, :object, fn -> extract_field(result, :object) end)

    Response.new(
      id: extract_field(result, :id),
      provider: client.provider,
      model: request.model || client.model || model_id(extract_field(result, :model)),
      text: text,
      object: object,
      tool_calls: extract_field(result, :tool_calls) || [],
      usage: usage,
      finish_reason: finish_reason || extract_field(result, :stop_reason),
      raw: result,
      metadata: metadata,
      trace:
        Trace.new(
          adapter: client.adapter,
          provider: client.provider,
          model: request.model || client.model,
          backend: client.backend,
          session: request.session,
          finish_reason: finish_reason,
          usage: usage,
          metadata: metadata
        )
    )
  end

  @spec normalize_error(term(), keyword()) :: Error.t()
  def normalize_error(reason, metadata \\ [])
  def normalize_error(%Error{} = error, _metadata), do: error
  def normalize_error(reason, metadata), do: Error.provider_error(reason, metadata)

  def extract_text(text) when is_binary(text), do: text
  def extract_text(nil), do: ""

  def extract_text(%module{} = result) do
    cond do
      function_exported?(module, :text, 1) ->
        result |> module.text() |> extract_text()

      Map.has_key?(result, :text) ->
        extract_text(Map.get(result, :text))

      Map.has_key?(result, :message) ->
        extract_text(Map.get(result, :message))

      true ->
        ""
    end
  end

  def extract_text(result) when is_map(result) do
    result[:text] || result["text"] || result[:message] || result["message"] || ""
  end

  def extract_text(result), do: inspect(result)

  def extract_field(%_module{} = result, field), do: Map.get(result, field)

  def extract_field(result, field) when is_map(result),
    do: result[field] || result[to_string(field)]

  def extract_field(_result, _field), do: nil

  def model_spec(%Client{} = client, %Request{} = request) do
    model = request.model || client.model

    case {client.provider, model} do
      {provider, model} when is_atom(provider) and is_binary(model) -> "#{provider}:#{model}"
      {_provider, model} when is_binary(model) -> model
      _ -> nil
    end
  end

  defp model_id(nil), do: nil
  defp model_id(model) when is_binary(model), do: model
  defp model_id(model) when is_map(model), do: model[:id] || model["id"]
  defp model_id(model), do: inspect(model)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
