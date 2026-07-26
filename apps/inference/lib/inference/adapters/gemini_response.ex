defmodule Inference.Adapters.GeminiResponse do
  @moduledoc false

  # Reads provider-reported fields out of a `gemini_ex` generate-content
  # response. Both shapes are understood: the SDK's own structs (snake_case
  # atom fields) and the raw API payload (camelCase string keys). Every reader
  # returns nil/empty when the provider did not report the field — nothing here
  # invents a value.

  @spec text(term()) :: String.t()
  def text(text) when is_binary(text), do: text

  def text(result) when is_map(result) do
    case map_value(result, :text) do
      direct when is_binary(direct) ->
        direct

      _other ->
        result
        |> candidates()
        |> Enum.flat_map(&candidate_text_parts/1)
        |> Enum.join("")
    end
  end

  def text(_result), do: ""

  @spec usage(term()) :: map() | nil
  def usage(result) when is_map(result) do
    result
    |> map_value(:usageMetadata, map_value(result, :usage_metadata))
    |> normalize_usage()
  end

  def usage(_result), do: nil

  @spec finish_reason(term()) :: term()
  def finish_reason(result) when is_map(result) do
    result
    |> candidates()
    |> Enum.find_value(&map_value(&1, :finishReason, map_value(&1, :finish_reason)))
  end

  def finish_reason(_result), do: nil

  @spec response_id(term()) :: term()
  def response_id(result) when is_map(result) do
    Enum.find_value([:response_id, :responseId, :id], &map_value(result, &1))
  end

  def response_id(_result), do: nil

  @spec model_version(term()) :: term()
  def model_version(result) when is_map(result),
    do: map_value(result, :modelVersion, map_value(result, :model_version))

  def model_version(_result), do: nil

  @spec tool_calls(term()) :: list()
  def tool_calls(result) when is_map(result) do
    result
    |> candidates()
    |> Enum.flat_map(&candidate_parts/1)
    |> Enum.flat_map(fn part ->
      case map_value(part, :functionCall, map_value(part, :function_call)) do
        nil -> []
        function_call -> [function_call]
      end
    end)
  end

  def tool_calls(_result), do: []

  @doc false
  @spec decode_object(term()) :: map() | nil
  def decode_object(text) when is_binary(text) do
    case JSON.decode(text) do
      {:ok, object} when is_map(object) -> object
      _other -> nil
    end
  end

  def decode_object(_text), do: nil

  @spec map_value(term(), atom(), term()) :: term()
  def map_value(map, key, default \\ nil)

  def map_value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  def map_value(_map, _key, default), do: default

  defp candidates(result), do: result |> map_value(:candidates, []) |> List.wrap()

  defp candidate_parts(candidate) when is_map(candidate) do
    candidate
    |> map_value(:content, %{})
    |> map_value(:parts, [])
    |> List.wrap()
  end

  defp candidate_parts(_candidate), do: []

  defp candidate_text_parts(candidate) do
    candidate
    |> candidate_parts()
    |> Enum.flat_map(fn part ->
      case map_value(part, :text) do
        text when is_binary(text) -> [text]
        _other -> []
      end
    end)
  end

  defp normalize_usage(usage) when is_map(usage) do
    %{
      input_tokens: map_value(usage, :promptTokenCount, map_value(usage, :prompt_token_count)),
      output_tokens:
        map_value(usage, :candidatesTokenCount, map_value(usage, :candidates_token_count)),
      total_tokens: map_value(usage, :totalTokenCount, map_value(usage, :total_token_count)),
      cached_tokens:
        map_value(usage, :cachedContentTokenCount, map_value(usage, :cached_content_token_count)),
      thoughts_tokens:
        map_value(usage, :thoughtsTokenCount, map_value(usage, :thoughts_token_count))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_usage(_usage), do: nil
end
