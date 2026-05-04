defmodule Inference do
  @moduledoc """
  Facade for semantic model inference.

  The facade accepts an `Inference.Client` and either prompt text, message
  lists, or an `Inference.Request`. Provider-specific behavior stays behind the
  configured adapter module.
  """

  alias Inference.{Client, Error, GovernedAuthority, Request}

  @doc """
  Builds a client.
  """
  @spec client(keyword() | map()) :: {:ok, Client.t()} | {:error, Error.t()}
  def client(attrs), do: Client.new(attrs)

  @doc """
  Builds a client or raises when invalid.
  """
  @spec client!(keyword() | map()) :: Client.t()
  def client!(attrs), do: Client.new!(attrs)

  @doc """
  Runs a completion through the configured adapter.
  """
  @spec complete(Client.t(), Request.input() | Request.t(), keyword()) ::
          {:ok, Inference.Response.t()} | {:error, Error.t()}
  def complete(%Client{} = client, input, opts \\ []) do
    with {:ok, request} <- Request.new(input, opts),
         :ok <- GovernedAuthority.reject_direct_request_options(client, request),
         :ok <- ensure_adapter(client.adapter, :complete, 2) do
      client.adapter.complete(client, request)
    end
  rescue
    exception ->
      {:error, Error.adapter_exception(exception, adapter: client.adapter)}
  end

  @doc """
  Starts a streaming completion when the adapter supports it.
  """
  @spec stream(Client.t(), Request.input() | Request.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Error.t()}
  def stream(%Client{} = client, input, opts \\ []) do
    with {:ok, request} <- Request.new(input, opts),
         :ok <- GovernedAuthority.reject_direct_request_options(client, request),
         :ok <- ensure_adapter(client.adapter, :stream, 2) do
      client.adapter.stream(client, request)
    end
  rescue
    exception ->
      {:error, Error.adapter_exception(exception, adapter: client.adapter)}
  end

  defp ensure_adapter(adapter, function, arity) when is_atom(adapter) do
    cond do
      not Code.ensure_loaded?(adapter) ->
        {:error, Error.missing_dependency(adapter)}

      not function_exported?(adapter, function, arity) ->
        {:error,
         Error.unsupported_capability(function,
           adapter: adapter,
           message: "#{inspect(adapter)} does not implement #{function}/#{arity}"
         )}

      true ->
        :ok
    end
  end
end
