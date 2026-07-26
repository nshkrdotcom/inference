defmodule Inference.Capability do
  @moduledoc """
  Data description of adapter/provider capabilities.

  Adapters report capabilities so a registry can answer questions such as "does
  this provider accept a JSON Schema response format?" BEFORE dispatch. A
  capability is a claim about the adapter and the provider it is bound to; an
  adapter that cannot establish a claim reports `:unknown` rather than assuming
  support.
  """

  defstruct [:name, support: :unknown, metadata: %{}]

  @supports [:supported, :unsupported, :partial, :provider_dependent, :unknown]

  @type support :: :supported | :unsupported | :partial | :provider_dependent | :unknown
  @type t :: %__MODULE__{name: atom(), support: support(), metadata: map()}

  @doc "Returns the closed set of support states."
  @spec supports() :: [support()]
  def supports, do: @supports

  @doc "Builds a capability claim."
  @spec new(atom(), support(), map()) :: t()
  def new(name, support, metadata \\ %{})
      when is_atom(name) and support in @supports and is_map(metadata) do
    %__MODULE__{name: name, support: support, metadata: metadata}
  end

  @doc "Fetches a named capability from a capability list."
  @spec fetch([t()], atom()) :: {:ok, t()} | :error
  def fetch(capabilities, name) when is_list(capabilities) and is_atom(name) do
    case Enum.find(capabilities, &(&1.name == name)) do
      nil -> :error
      capability -> {:ok, capability}
    end
  end

  @doc "Fetches a named capability or raises when the adapter does not report it."
  @spec fetch!([t()], atom()) :: t()
  def fetch!(capabilities, name) do
    case fetch(capabilities, name) do
      {:ok, capability} ->
        capability

      :error ->
        raise ArgumentError, "capability #{inspect(name)} was not reported"
    end
  end

  @doc """
  Reports whether a named capability is affirmatively supported.

  Unknown, partial, provider-dependent, and unreported capabilities are all
  false: only an affirmative `:supported` claim answers yes.
  """
  @spec supported?([t()], atom()) :: boolean()
  def supported?(capabilities, name) do
    case fetch(capabilities, name) do
      {:ok, %__MODULE__{support: :supported}} -> true
      _other -> false
    end
  end
end
