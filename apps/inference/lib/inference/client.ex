defmodule Inference.Client do
  @moduledoc """
  Adapter client configuration.
  """

  alias Inference.{Adapter, Error, GovernedAuthority}

  @default_admitted_kinds [:model_endpoint, :local_model_endpoint]

  @enforce_keys [:adapter]
  defstruct [
    :adapter,
    :provider,
    :model,
    :backend,
    :authority,
    admitted_kinds: @default_admitted_kinds,
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
          authority: map() | nil,
          admitted_kinds: [Adapter.provider_kind()],
          defaults: keyword(),
          capabilities: list(),
          metadata: map(),
          adapter_opts: keyword()
        }

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, Error.t()}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    with {:ok, attrs} <- GovernedAuthority.materialize_client_attrs(attrs) do
      client = %__MODULE__{
        adapter: fetch(attrs, :adapter),
        provider: fetch(attrs, :provider),
        model: fetch(attrs, :model),
        backend: fetch(attrs, :backend),
        authority: fetch(attrs, :authority),
        admitted_kinds: fetch(attrs, :admitted_kinds, @default_admitted_kinds),
        defaults: fetch(attrs, :defaults, []),
        capabilities: fetch(attrs, :capabilities, []),
        metadata: fetch(attrs, :metadata, %{}),
        adapter_opts: fetch(attrs, :adapter_opts, [])
      }

      validate(client)
    end
  end

  def new(other), do: {:error, Error.invalid(:client, "client attrs must be a map", value: other)}

  @doc "Validates that the configured adapter reports an explicitly admitted kind."
  @spec validate_adapter_kind(t()) :: :ok | {:error, Error.t()}
  def validate_adapter_kind(%__MODULE__{adapter: adapter, admitted_kinds: admitted_kinds}) do
    cond do
      not Code.ensure_loaded?(adapter) ->
        {:error, Error.missing_dependency(adapter)}

      not function_exported?(adapter, :provider_kind, 0) ->
        {:error,
         Error.unsupported_capability(:provider_kind,
           adapter: adapter,
           admitted_kinds: admitted_kinds,
           message: "#{inspect(adapter)} does not implement provider_kind/0"
         )}

      true ->
        validate_reported_kind(adapter, adapter.provider_kind(), admitted_kinds)
    end
  end

  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, client} -> client
      {:error, error} -> raise ArgumentError, Exception.message(error)
    end
  end

  @doc """
  Builds a client that additionally admits `:agent_session` adapters.

  The default admitted-kind set deliberately excludes `:agent_session` so an
  agent-session runtime is never silently flattened into a completion endpoint.
  This is the explicit, per-client opt-in; it widens one client, never the
  default.
  """
  @spec agent_session(keyword() | map()) :: {:ok, t()} | {:error, Error.t()}
  def agent_session(attrs) when is_list(attrs), do: attrs |> Map.new() |> agent_session()

  def agent_session(attrs) when is_map(attrs) do
    admitted_kinds = fetch(attrs, :admitted_kinds, @default_admitted_kinds)

    if is_list(admitted_kinds) do
      new(Map.put(attrs, :admitted_kinds, admitted_kinds ++ [:agent_session]))
    else
      new(attrs)
    end
  end

  def agent_session(other), do: new(other)

  @doc """
  Builds an agent-session-admitting client or raises when invalid.
  """
  @spec agent_session!(keyword() | map()) :: t()
  def agent_session!(attrs) do
    case agent_session(attrs) do
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

  defp validate(%__MODULE__{admitted_kinds: admitted_kinds}) when not is_list(admitted_kinds) do
    {:error,
     Error.invalid(:admitted_kinds, "admitted_kinds must be a list",
       admitted_kinds: admitted_kinds
     )}
  end

  defp validate(%__MODULE__{admitted_kinds: admitted_kinds} = client) do
    invalid_kinds = Enum.reject(admitted_kinds, &Adapter.valid_provider_kind?/1)

    if invalid_kinds == [] do
      {:ok, %{client | admitted_kinds: Enum.uniq(admitted_kinds)}}
    else
      {:error,
       Error.invalid(:admitted_kinds, "admitted_kinds contains an invalid provider kind",
         admitted_kinds: admitted_kinds,
         invalid_kinds: invalid_kinds,
         valid_kinds: Adapter.provider_kinds()
       )}
    end
  end

  defp validate_reported_kind(adapter, provider_kind, admitted_kinds) do
    cond do
      not Adapter.valid_provider_kind?(provider_kind) ->
        {:error,
         Error.invalid(:provider_kind, "adapter reported an invalid provider kind",
           adapter: adapter,
           provider_kind: provider_kind,
           valid_kinds: Adapter.provider_kinds()
         )}

      provider_kind in admitted_kinds ->
        :ok

      true ->
        {:error,
         Error.unsupported_capability(:provider_kind,
           adapter: adapter,
           provider_kind: provider_kind,
           admitted_kinds: admitted_kinds,
           message: "#{inspect(adapter)} provider kind #{inspect(provider_kind)} is not admitted"
         )}
    end
  end

  defp fetch(attrs, key, default \\ nil),
    do: Map.get(attrs, key) || Map.get(attrs, to_string(key), default)
end
