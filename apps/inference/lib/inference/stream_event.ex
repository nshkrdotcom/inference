defmodule Inference.StreamEvent do
  @moduledoc """
  Provider-neutral streaming event.
  """

  defstruct [:type, :data, metadata: %{}]

  @type type :: :delta | :message | :tool_call | :done | :error | atom()
  @type t :: %__MODULE__{type: type(), data: term(), metadata: map()}
end
