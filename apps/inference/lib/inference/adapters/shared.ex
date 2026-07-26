defmodule Inference.Adapters.Shared do
  @moduledoc false

  alias Inference.Adapters.ProviderError
  alias Inference.{Client, Error, Request, Response, Trace}

  @spec ensure_dependency(module()) :: :ok | {:error, Error.t()}
  def ensure_dependency(module) do
    if Code.ensure_loaded?(module) do
      :ok
    else
      {:error, Error.missing_dependency(module)}
    end
  end

  # `response_format` is deliberately NOT part of this bag: it is a
  # provider-neutral declaration each adapter must map onto a real provider
  # option or refuse. Passing it through opaquely is how it used to be dropped.
  @spec request_opts(Client.t(), Request.t()) :: keyword()
  def request_opts(%Client{} = client, %Request{} = request) do
    client.defaults
    |> Keyword.merge(request.options)
    |> maybe_put(:model, request.model || client.model)
    |> maybe_put(:temperature, request.temperature)
    |> maybe_put(:top_p, request.top_p)
    |> maybe_put(:max_tokens, request.max_tokens)
  end

  @doc """
  Rejects provider tool options on a completion-only adapter.

  `metadata` carries the adapter module and a `:message_prefix` describing the
  adapter's own tool posture.
  """
  @spec reject_tool_options(keyword(), [atom()], keyword()) :: :ok | {:error, Error.t()}
  def reject_tool_options(opts, tool_keys, metadata) when is_list(opts) do
    {prefix, metadata} = Keyword.pop!(metadata, :message_prefix)

    case Enum.find(tool_keys, &Keyword.has_key?(opts, &1)) do
      nil ->
        :ok

      key ->
        {:error,
         Error.unsupported_capability(
           :tools,
           Keyword.merge(metadata, message: "#{prefix}; rejected #{inspect(key)}", key: key)
         )}
    end
  end

  @doc """
  Fails closed when a completion-only provider returns a tool call.
  """
  @spec reject_tool_calls(term(), list(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def reject_tool_calls(result, tool_calls, metadata) do
    case tool_calls do
      [] -> {:ok, result}
      tool_calls -> {:error, Error.unexpected_tool_call(tool_calls, metadata)}
    end
  end

  @spec response_from_result(term(), Client.t(), Request.t(), keyword()) :: Response.t()
  def response_from_result(result, %Client{} = client, %Request{} = request, opts \\ []) do
    text = Keyword.get_lazy(opts, :text, fn -> extract_text(result) end)
    usage = Keyword.get_lazy(opts, :usage, fn -> extract_field(result, :usage) end)
    cost = Keyword.get_lazy(opts, :cost, fn -> extract_field(result, :cost) end)

    finish_reason =
      Keyword.get_lazy(opts, :finish_reason, fn -> extract_field(result, :finish_reason) end)

    metadata = Map.merge(client.metadata, Keyword.get(opts, :metadata, %{}))
    object = Keyword.get_lazy(opts, :object, fn -> extract_field(result, :object) end)

    Response.new(
      id: Keyword.get_lazy(opts, :id, fn -> extract_field(result, :id) end),
      provider: client.provider,
      model: request.model || client.model || model_id(extract_field(result, :model)),
      text: text,
      object: object,
      tool_calls: extract_field(result, :tool_calls) || [],
      usage: usage,
      cost: cost,
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
          cost: cost,
          metadata: metadata
        )
    )
  end

  @spec normalize_error(term(), keyword()) :: Error.t()
  def normalize_error(reason, metadata \\ []), do: ProviderError.normalize(reason, metadata)

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
      {provider, model} when is_atom(provider) and is_binary(model) ->
        Atom.to_string(provider) <> ":" <> model

      {_provider, model} when is_binary(model) ->
        model

      _ ->
        nil
    end
  end

  defp model_id(nil), do: nil
  defp model_id(model) when is_binary(model), do: model
  defp model_id(model) when is_map(model), do: model[:id] || model["id"]
  defp model_id(model), do: inspect(model)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
