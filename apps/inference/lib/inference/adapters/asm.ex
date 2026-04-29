defmodule Inference.Adapters.ASM do
  @moduledoc """
  Adapter for Agent Session Manager.

  The consuming application must install and configure `:agent_session_manager`.
  """

  @behaviour Inference.Adapter

  alias Inference.Adapters.Shared
  alias Inference.{Client, Error, Request}

  @impl true
  def complete(%Client{} = client, %Request{} = request) do
    module = Keyword.get(client.adapter_opts, :asm_module, ASM)

    with :ok <- Shared.ensure_dependency(module),
         target <-
           request.session || Keyword.get(client.adapter_opts, :session) || client.provider,
         :ok <- validate_target(target),
         opts <- Shared.request_opts(client, request),
         {:ok, result} <- call_query(module, target, Request.to_prompt(request), opts) do
      metadata = %{
        run_id: Shared.extract_field(result, :run_id),
        session_id: Shared.extract_field(result, :session_id),
        cost: Shared.extract_field(result, :cost),
        duration_ms: Shared.extract_field(result, :duration_ms)
      }

      {:ok, Shared.response_from_result(result, client, request, metadata: metadata)}
    else
      {:error, reason} -> {:error, Shared.normalize_error(reason, adapter: __MODULE__)}
    end
  end

  @impl true
  def stream(%Client{} = _client, %Request{} = _request) do
    {:error, Error.unsupported_capability(:stream, adapter: __MODULE__)}
  end

  defp validate_target(nil),
    do: {:error, Error.invalid(:provider, "ASM provider or session is required")}

  defp validate_target(_target), do: :ok

  defp call_query(module, target, prompt, opts) do
    if function_exported?(module, :query, 3) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(module, :query, [target, prompt, opts])
    else
      {:error, Error.missing_dependency(module, function: :query)}
    end
  end
end
