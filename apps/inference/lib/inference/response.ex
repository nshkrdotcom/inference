defmodule Inference.Response do
  @moduledoc """
  Provider-neutral inference response.
  """

  defstruct [
    :id,
    :provider,
    :model,
    :text,
    :object,
    :tool_calls,
    :usage,
    :cost,
    :finish_reason,
    :raw,
    :metadata,
    :trace
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          provider: atom() | nil,
          model: String.t() | nil,
          text: String.t(),
          object: map() | nil,
          tool_calls: list(),
          usage: map() | nil,
          cost: map() | number() | nil,
          finish_reason: atom() | String.t() | nil,
          raw: term(),
          metadata: map(),
          trace: Inference.Trace.t() | map() | nil
        }

  @spec new(keyword() | map()) :: t()
  def new(attrs \\ []) do
    attrs = if is_list(attrs), do: Map.new(attrs), else: attrs

    %__MODULE__{
      id: fetch(attrs, :id),
      provider: fetch(attrs, :provider),
      model: fetch(attrs, :model),
      text: normalize_text(fetch(attrs, :text)),
      object: fetch(attrs, :object),
      tool_calls: fetch(attrs, :tool_calls, []),
      usage: fetch(attrs, :usage),
      cost: fetch(attrs, :cost),
      finish_reason: fetch(attrs, :finish_reason),
      raw: fetch(attrs, :raw),
      metadata: fetch(attrs, :metadata, %{}),
      trace: fetch(attrs, :trace)
    }
  end

  @spec text(t() | nil) :: String.t()
  def text(nil), do: ""
  def text(%__MODULE__{text: text}), do: normalize_text(text)
  def text(text) when is_binary(text), do: text
  def text(_), do: ""

  defp normalize_text(nil), do: ""
  defp normalize_text(text) when is_binary(text), do: text
  defp normalize_text(text), do: inspect(text)

  defp fetch(attrs, key, default \\ nil),
    do: Map.get(attrs, key) || Map.get(attrs, to_string(key), default)
end
