defmodule Inference.Redaction do
  @moduledoc """
  Redacts secrets from metadata before persistence.
  """

  @secret_key_fragments ~w[
    api_key apikey authorization bearer credential credentials password secret token
  ]

  @spec redact(term()) :: term()
  def redact(%_struct{} = value) do
    value
    |> Map.from_struct()
    |> redact()
  end

  def redact(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      if secret_key?(key) do
        {key, "[REDACTED]"}
      else
        {key, redact(value)}
      end
    end)
  end

  def redact(list) when is_list(list), do: Enum.map(list, &redact/1)
  def redact(value), do: value

  defp secret_key?(key) do
    normalized =
      key
      |> to_string()
      |> String.downcase()

    Enum.any?(@secret_key_fragments, &String.contains?(normalized, &1))
  end
end
