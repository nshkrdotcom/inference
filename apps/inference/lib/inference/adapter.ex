defmodule Inference.Adapter do
  @moduledoc """
  Behaviour implemented by inference adapter modules.
  """

  @provider_kinds [:model_endpoint, :local_model_endpoint, :agent_session]

  @type provider_kind :: :model_endpoint | :local_model_endpoint | :agent_session

  @callback provider_kind() :: provider_kind()

  @callback complete(Inference.Client.t(), Inference.Request.t()) ::
              {:ok, Inference.Response.t()} | {:error, Inference.Error.t()}

  @callback stream(Inference.Client.t(), Inference.Request.t()) ::
              {:ok, Enumerable.t()} | {:error, Inference.Error.t()}

  @optional_callbacks stream: 2

  @doc "Returns the closed set of valid provider kinds."
  @spec provider_kinds() :: [provider_kind()]
  def provider_kinds, do: @provider_kinds

  @doc "Reports whether a value belongs to the closed provider-kind set."
  @spec valid_provider_kind?(term()) :: boolean()
  def valid_provider_kind?(kind), do: kind in @provider_kinds
end
