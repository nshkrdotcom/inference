defmodule Inference.ResponseFormat do
  @moduledoc """
  Provider-neutral response format.

  The union is closed. A request either leaves the format unspecified (`nil`)
  or declares exactly one of:

    * `:text` — plain assistant text.
    * `{:json, :object}` — schemaless JSON object mode.
    * `{:json_schema, %{name: name, schema: schema, strict: strict?}}` — a named
      schema the provider must conform to.

  Every adapter either maps the declared format onto a real provider option or
  refuses it with `Inference.Error.response_format_unsupported/2`. Silently
  dropping a declared format is a contract violation, not a fallback.
  """

  alias Inference.Error

  @json_schema_keys [:name, :schema, :strict]

  @type json_schema :: %{
          required(:name) => String.t(),
          required(:schema) => map() | keyword(),
          required(:strict) => boolean()
        }

  @type t :: :text | {:json, :object} | {:json_schema, json_schema()}

  @doc """
  Normalizes a caller-supplied response format into the closed union.

  `nil` stays `nil` and means "unspecified". Anything outside the union is an
  `:invalid` error with reason `:response_format`.
  """
  @spec normalize(term()) :: {:ok, t() | nil} | {:error, Error.t()}
  def normalize(nil), do: {:ok, nil}
  def normalize(:text), do: {:ok, :text}
  def normalize({:json, :object}), do: {:ok, {:json, :object}}

  def normalize({:json_schema, spec}) when is_map(spec) do
    with :ok <- validate_json_schema_keys(spec),
         {:ok, name} <- fetch_name(spec),
         {:ok, schema} <- fetch_schema(spec),
         {:ok, strict} <- fetch_strict(spec) do
      {:ok, {:json_schema, %{name: name, schema: schema, strict: strict}}}
    end
  end

  def normalize(other), do: {:error, invalid(other)}

  @doc "Returns true when the format asks the provider for JSON output."
  @spec json?(t() | nil) :: boolean()
  def json?({:json, :object}), do: true
  def json?({:json_schema, _spec}), do: true
  def json?(_response_format), do: false

  defp validate_json_schema_keys(spec) do
    case Map.keys(spec) -- @json_schema_keys do
      [] -> :ok
      unknown -> {:error, invalid({:json_schema, spec}, unknown_keys: Enum.sort(unknown))}
    end
  end

  defp fetch_name(spec) do
    case Map.get(spec, :name) do
      name when is_binary(name) and name != "" -> {:ok, name}
      _other -> {:error, invalid({:json_schema, spec}, field: :name)}
    end
  end

  defp fetch_schema(spec) do
    case Map.get(spec, :schema) do
      schema when is_map(schema) and map_size(schema) > 0 -> {:ok, schema}
      [_ | _] = schema -> keyword_schema(spec, schema)
      _other -> {:error, invalid({:json_schema, spec}, field: :schema)}
    end
  end

  defp keyword_schema(spec, schema) do
    if Keyword.keyword?(schema) do
      {:ok, schema}
    else
      {:error, invalid({:json_schema, spec}, field: :schema)}
    end
  end

  defp fetch_strict(spec) do
    case Map.get(spec, :strict, true) do
      strict when is_boolean(strict) -> {:ok, strict}
      _other -> {:error, invalid({:json_schema, spec}, field: :strict)}
    end
  end

  defp invalid(value, metadata \\ []) do
    Error.invalid(
      :response_format,
      "response_format must be nil, :text, {:json, :object}, or " <>
        "{:json_schema, %{name: String.t(), schema: map() | keyword(), strict: boolean()}}",
      Keyword.put(metadata, :response_format, value)
    )
  end
end
