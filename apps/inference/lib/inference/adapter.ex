defmodule Inference.Adapter do
  @moduledoc """
  Behaviour implemented by inference adapter modules.
  """

  @callback complete(Inference.Client.t(), Inference.Request.t()) ::
              {:ok, Inference.Response.t()} | {:error, Inference.Error.t()}

  @callback stream(Inference.Client.t(), Inference.Request.t()) ::
              {:ok, Enumerable.t()} | {:error, Inference.Error.t()}

  @optional_callbacks stream: 2
end
