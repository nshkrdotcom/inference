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

  @optional_callbacks stream: 2, credential_mode: 0

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
end
