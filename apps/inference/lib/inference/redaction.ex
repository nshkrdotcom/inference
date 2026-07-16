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
    Map.new(map, &redact_entry(&1, redaction_values))
  end

  defp redact(list, redaction_values) when is_list(list) do
    if Keyword.keyword?(list) do
      Enum.map(list, &redact_entry(&1, redaction_values))
    else
      Enum.map(list, &redact(&1, redaction_values))
    end
  end

  defp redact(tuple, redaction_values) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&redact(&1, redaction_values))
    |> List.to_tuple()
  end

  defp redact(value, redaction_values) when is_binary(value) do
    Enum.reduce(redaction_values, value, fn redaction_value, acc ->
      String.replace(acc, redaction_value, "[REDACTED]")
    end)
  end

  defp redact(value, _redaction_values), do: value

  defp redact_entry({key, value}, redaction_values) do
    if secret_key?(key) do
      {key, "[REDACTED]"}
    else
      {key, redact(value, redaction_values)}
    end
  end

  defp collect_redaction_values(%_struct{} = value) do
    value
    |> Map.from_struct()
    |> collect_redaction_values()
  end

  defp collect_redaction_values(map) when is_map(map) do
    own_values = redaction_values_from(map) ++ secret_values_from(map)

    child_values =
      map
      |> Map.values()
      |> Enum.flat_map(&collect_redaction_values/1)

    Enum.uniq(own_values ++ child_values)
  end

  defp collect_redaction_values(list) when is_list(list) do
    if Keyword.keyword?(list) do
      Enum.flat_map(list, &redaction_values_from_entry/1)
    else
      Enum.flat_map(list, &collect_redaction_values/1)
    end
  end

  defp collect_redaction_values(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.flat_map(&collect_redaction_values/1)
  end

  defp collect_redaction_values(_value), do: []

  defp redaction_values_from_entry({key, value}) do
    own_values = if secret_key?(key), do: binary_values(value), else: []
    own_values ++ collect_redaction_values(value)
  end

  defp redaction_values_from(map) do
    values = Map.get(map, :redaction_values) || Map.get(map, "redaction_values") || []

    values
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp secret_values_from(map) do
    Enum.flat_map(map, fn {key, value} ->
      if secret_key?(key), do: binary_values(value), else: []
    end)
  end

  defp binary_values(""), do: []
  defp binary_values(value) when is_binary(value), do: [value]

  defp binary_values(%_struct{} = value) do
    value
    |> Map.from_struct()
    |> binary_values()
  end

  defp binary_values(map) when is_map(map),
    do: map |> Map.values() |> Enum.flat_map(&binary_values/1)

  defp binary_values(list) when is_list(list), do: Enum.flat_map(list, &binary_values/1)
  defp binary_values(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> binary_values()
  defp binary_values(_value), do: []

  defp secret_key?(key) do
    normalized =
      key
      |> to_string()
      |> String.downcase()

    not safe_reference_key?(normalized) and
      Enum.any?(@secret_key_fragments, &String.contains?(normalized, &1))
  end

  defp safe_reference_key?(key) do
    Enum.any?(~w[_ref _refs _id _ids _generation _fence], &String.ends_with?(key, &1))
  end
end
