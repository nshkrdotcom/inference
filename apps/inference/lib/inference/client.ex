defmodule Inference.Client do
  @moduledoc """
  Adapter client configuration.
  """

  alias Inference.Error

  @enforce_keys [:adapter]
  defstruct [
    :adapter,
    :provider,
    :model,
    :backend,
    defaults: [],
    capabilities: [],
    metadata: %{},
    adapter_opts: []
  ]

  @type t :: %__MODULE__{
          adapter: module(),
          provider: atom() | nil,
          model: String.t() | nil,
          backend: atom() | nil,
          defaults: keyword(),
          capabilities: list(),
          metadata: map(),
          adapter_opts: keyword()
        }

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Error.t()}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    client = %__MODULE__{
      adapter: fetch(attrs, :adapter),
      provider: fetch(attrs, :provider),
      model: fetch(attrs, :model),
      backend: fetch(attrs, :backend),
      defaults: fetch(attrs, :defaults, []),
      capabilities: fetch(attrs, :capabilities, []),
      metadata: fetch(attrs, :metadata, %{}),
      adapter_opts: fetch(attrs, :adapter_opts, [])
    }

    validate(client)
  end

  def new(other), do: {:error, Error.invalid(:client, "client attrs must be a map", value: other)}

  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, client} -> client
      {:error, error} -> raise ArgumentError, Exception.message(error)
    end
  end

  defp validate(%__MODULE__{adapter: adapter}) when not is_atom(adapter) do
    {:error, Error.invalid(:adapter, "adapter must be a module atom", adapter: adapter)}
  end

  defp validate(%__MODULE__{defaults: defaults}) when not is_list(defaults) do
    {:error, Error.invalid(:defaults, "defaults must be a keyword list", defaults: defaults)}
  end

  defp validate(%__MODULE__{adapter_opts: adapter_opts}) when not is_list(adapter_opts) do
    {:error, Error.invalid(:adapter_opts, "adapter_opts must be a keyword list")}
  end

  defp validate(%__MODULE__{metadata: metadata}) when not is_map(metadata) do
    {:error, Error.invalid(:metadata, "metadata must be a map")}
  end

  defp validate(%__MODULE__{} = client), do: {:ok, client}

  defp fetch(attrs, key, default \\ nil),
    do: Map.get(attrs, key) || Map.get(attrs, to_string(key), default)
end
