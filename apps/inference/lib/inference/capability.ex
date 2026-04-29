defmodule Inference.Capability do
  @moduledoc """
  Data description of adapter/provider capabilities.
  """

  defstruct [:name, support: :unknown, metadata: %{}]

  @type support :: :supported | :unsupported | :partial | :provider_dependent | :unknown
  @type t :: %__MODULE__{name: atom(), support: support(), metadata: map()}
end
