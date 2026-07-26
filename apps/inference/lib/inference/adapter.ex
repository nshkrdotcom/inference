defmodule Inference.Adapter do
  @moduledoc """
  Behaviour implemented by inference adapter modules.

  Direct provider adapters use the default `:explicit` credential mode. A
  managed authority adapter must explicitly report `:managed_materialization`
  and owns lease redemption and transient provider material outside this
  package.
  """

  @provider_kinds [:model_endpoint, :local_model_endpoint, :agent_session]
  @credential_modes [:explicit, :managed_materialization]

  @type provider_kind :: :model_endpoint | :local_model_endpoint | :agent_session
  @type credential_mode :: :explicit | :managed_materialization

  @callback provider_kind() :: provider_kind()

  @callback credential_mode() :: credential_mode()

  @callback complete(Inference.Client.t(), Inference.Request.t()) ::
              {:ok, Inference.Response.t()} | {:error, Inference.Error.t()}

  @callback stream(Inference.Client.t(), Inference.Request.t()) ::
              {:ok, Enumerable.t()} | {:error, Inference.Error.t()}

  @doc """
  Reports what this adapter can do for the given client's provider binding.

  Adapters that can answer capability questions implement this callback; the
  answer must come from a real provider feature declaration, never a guess.
  """
  @callback capabilities(Inference.Client.t()) :: [Inference.Capability.t()]

  @optional_callbacks stream: 2, credential_mode: 0, capabilities: 1

  @doc "Returns the closed set of valid provider kinds."
  @spec provider_kinds() :: [provider_kind()]
  def provider_kinds, do: @provider_kinds

  @doc "Returns the closed set of credential modes."
  @spec credential_modes() :: [credential_mode()]
  def credential_modes, do: @credential_modes

  @doc "Reports an adapter's credential mode; existing direct adapters are explicit."
  @spec credential_mode(module()) :: credential_mode() | :invalid
  def credential_mode(adapter) when is_atom(adapter) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :credential_mode, 0) do
      case adapter.credential_mode() do
        mode when mode in @credential_modes -> mode
        _other -> :invalid
      end
    else
      :explicit
    end
  end

  @doc "Reports whether a value belongs to the closed provider-kind set."
  @spec valid_provider_kind?(term()) :: boolean()
  def valid_provider_kind?(kind), do: kind in @provider_kinds

  @doc """
  Resolves the capabilities of a configured client.

  Adapters that implement `c:capabilities/1` answer for their provider binding.
  Adapters that do not fall back to the client's declared capabilities.
  """
  @spec capabilities(Inference.Client.t()) :: [Inference.Capability.t()]
  def capabilities(client) do
    adapter = client.adapter

    if is_atom(adapter) and Code.ensure_loaded?(adapter) and
         function_exported?(adapter, :capabilities, 1) do
      adapter.capabilities(client)
    else
      client.capabilities
    end
  end
end
