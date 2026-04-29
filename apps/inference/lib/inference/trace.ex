defmodule Inference.Trace do
  @moduledoc """
  Redactable provider execution summary.
  """

  defstruct [
    :adapter,
    :provider,
    :model,
    :backend,
    :session,
    :duration_ms,
    :finish_reason,
    :usage,
    :cost,
    :error,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          adapter: module() | nil,
          provider: atom() | nil,
          model: String.t() | nil,
          backend: atom() | nil,
          session: term(),
          duration_ms: non_neg_integer() | nil,
          finish_reason: atom() | String.t() | nil,
          usage: map() | nil,
          cost: map() | number() | nil,
          error: atom() | nil,
          metadata: map()
        }

  @spec new(keyword() | map()) :: t()
  def new(attrs \\ []) do
    attrs = if is_list(attrs), do: Map.new(attrs), else: attrs

    %__MODULE__{
      adapter: attrs[:adapter],
      provider: attrs[:provider],
      model: attrs[:model],
      backend: attrs[:backend],
      session: attrs[:session],
      duration_ms: attrs[:duration_ms],
      finish_reason: attrs[:finish_reason],
      usage: attrs[:usage],
      cost: attrs[:cost],
      error: attrs[:error],
      metadata: attrs[:metadata] || %{}
    }
  end

  @spec redact(t() | map()) :: map()
  def redact(%__MODULE__{} = trace),
    do: trace |> Map.from_struct() |> Inference.Redaction.redact()

  def redact(trace) when is_map(trace), do: Inference.Redaction.redact(trace)
end
