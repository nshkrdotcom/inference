defmodule Inference.Redaction do
  @moduledoc """
  Redacts secrets from metadata before persistence.
  """

  @secret_key_fragments ~w[
    api_key apikey authorization bearer credential credentials password secret token
  ]

  @spec redact(term()) :: term()
  def redact(value) do
    value
    |> collect_redaction_values()
    |> then(&redact(value, &1))
  end

  defp redact(%_struct{} = value, redaction_values) do
    value
    |> Map.from_struct()
    |> redact(redaction_values)
  end

  defp redact(map, redaction_values) when is_map(map) do
    Map.new(map, fn {key, value} ->
      if secret_key?(key) do
        {key, "[REDACTED]"}
      else
        {key, redact(value, redaction_values)}
      end
    end)
  end

  defp redact(list, redaction_values) when is_list(list) do
    Enum.map(list, &redact(&1, redaction_values))
  end

  defp redact(value, redaction_values) when is_binary(value) do
    Enum.reduce(redaction_values, value, fn redaction_value, acc ->
      String.replace(acc, redaction_value, "[REDACTED]")
    end)
  end

  defp redact(value, _redaction_values), do: value

  defp collect_redaction_values(%_struct{} = value) do
    value
    |> Map.from_struct()
    |> collect_redaction_values()
  end

  defp collect_redaction_values(map) when is_map(map) do
    own_values = redaction_values_from(map)

    child_values =
      map
      |> Map.values()
      |> Enum.flat_map(&collect_redaction_values/1)

    Enum.uniq(own_values ++ child_values)
  end

  defp collect_redaction_values(list) when is_list(list) do
    Enum.flat_map(list, &collect_redaction_values/1)
  end

  defp collect_redaction_values(_value), do: []

  defp redaction_values_from(map) do
    values = Map.get(map, :redaction_values) || Map.get(map, "redaction_values") || []

    values
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp secret_key?(key) do
    normalized =
      key
      |> to_string()
      |> String.downcase()

    Enum.any?(@secret_key_fragments, &String.contains?(normalized, &1))
  end
end
