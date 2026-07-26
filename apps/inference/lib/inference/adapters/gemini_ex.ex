defmodule Inference.Adapters.GeminiEx do
  @moduledoc """
  Adapter for the owned `gemini_ex` SDK.

  The adapter calls the SDK's structured `generate/2` entry point and maps the
  provider-reported response: text, object, usage, finish reason, response id,
  and model version. The SDK's `text/2` entry point is deliberately NOT used —
  its `{:ok, String.t()}` contract discards every one of those fields.

  Requests are completion-only: tools and tool configuration are refused, and a
  provider-returned function call is a typed contract failure.
  """

  @behaviour Inference.Adapter

  alias Inference.Adapters.{GeminiResponse, Shared}
  alias Inference.{Capability, Client, Error, Request, ResponseFormat}

  @tool_keys [:tools, :tool_choice, :tool_config, :function_declarations, :functions]
  @tool_message_prefix "Gemini adapter is completion-only and does not accept tools or tool configuration"
  @json_mime_type "application/json"

  @impl true
  def provider_kind, do: :model_endpoint

  @impl true
  def complete(%Client{} = client, %Request{} = request) do
    module = Keyword.get(client.adapter_opts, :gemini_module, Gemini)

    with :ok <- Shared.ensure_dependency(module),
         {:ok, opts} <- generation_opts(client, request),
         {:ok, result} <- call_generate(module, Request.user_prompt(request), opts),
         {:ok, result} <- reject_tool_calls(result) do
      {:ok, response(result, client, request)}
    else
      {:error, reason} -> {:error, Shared.normalize_error(reason, adapter: __MODULE__)}
    end
  end

  @impl true
  def stream(%Client{} = _client, %Request{} = _request) do
    {:error, Error.unsupported_capability(:stream, adapter: __MODULE__)}
  end

  @impl true
  def capabilities(%Client{} = _client) do
    [
      Capability.new(:response_format_text, :supported),
      Capability.new(:response_format_json_object, :supported, %{
        generation_option: :response_mime_type
      }),
      Capability.new(:response_format_json_schema, :supported, %{
        generation_option: :response_json_schema
      }),
      Capability.new(:tools, :unsupported, %{profile: :completion_only}),
      Capability.new(:streaming, :unsupported, %{
        message: "incremental Gemini delivery lives in Inference.Adapters.GeminiExManaged"
      })
    ]
  end

  defp call_generate(module, prompt, opts) do
    if function_exported?(module, :generate, 2) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(module, :generate, [prompt, opts])
    else
      {:error, Error.missing_dependency(module, function: :generate, arity: 2)}
    end
  end

  defp generation_opts(%Client{} = client, %Request{} = request) do
    opts =
      client
      |> Shared.request_opts(request)
      |> rename_max_tokens()

    with :ok <-
           Shared.reject_tool_options(opts, @tool_keys,
             adapter: __MODULE__,
             message_prefix: @tool_message_prefix
           ),
         {:ok, format_opts} <- response_format_opts(request) do
      {:ok, Keyword.merge(opts, format_opts)}
    end
  end

  defp rename_max_tokens(opts) do
    case Keyword.pop(opts, :max_tokens) do
      {nil, renamed} -> renamed
      {max_tokens, renamed} -> Keyword.put_new(renamed, :max_output_tokens, max_tokens)
    end
  end

  # Gemini structured output rides the generation config: `responseJsonSchema`
  # for a declared JSON Schema, `responseMimeType` for JSON object mode.
  defp response_format_opts(%Request{response_format: nil}), do: {:ok, []}
  defp response_format_opts(%Request{response_format: :text}), do: {:ok, []}

  defp response_format_opts(%Request{response_format: {:json, :object}}),
    do: {:ok, [response_mime_type: @json_mime_type]}

  defp response_format_opts(%Request{response_format: {:json_schema, %{schema: schema}}})
       when is_map(schema),
       do: {:ok, [response_json_schema: schema, response_mime_type: @json_mime_type]}

  defp response_format_opts(%Request{response_format: response_format}) do
    {:error,
     Error.response_format_unsupported(response_format,
       adapter: __MODULE__,
       message: "Gemini responseJsonSchema takes a JSON Schema map"
     )}
  end

  defp reject_tool_calls(result) do
    Shared.reject_tool_calls(result, GeminiResponse.tool_calls(result), adapter: __MODULE__)
  end

  defp response(result, %Client{} = client, %Request{} = request) do
    text = GeminiResponse.text(result)

    Shared.response_from_result(result, client, request,
      id: GeminiResponse.response_id(result),
      text: text,
      object: object(request, text),
      usage: GeminiResponse.usage(result),
      finish_reason: GeminiResponse.finish_reason(result),
      metadata: metadata(result)
    )
  end

  defp object(%Request{response_format: response_format}, text) do
    if ResponseFormat.json?(response_format), do: GeminiResponse.decode_object(text)
  end

  defp metadata(result) do
    case GeminiResponse.model_version(result) do
      nil -> %{}
      model_version -> %{model_version: model_version}
    end
  end
end
