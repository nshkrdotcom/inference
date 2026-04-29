defmodule Inference.Adapters.ReqLlmNext do
  @moduledoc """
  Adapter for ReqLlmNext broad hosted-provider coverage.
  """

  @behaviour Inference.Adapter

  alias Inference.Adapters.Shared
  alias Inference.{Client, Error, Request}

  @impl true
  def complete(%Client{} = client, %Request{} = request) do
    module = Keyword.get(client.adapter_opts, :executor_module, ReqLlmNext.Executor)

    with :ok <- Shared.ensure_dependency(module),
         model_spec when is_binary(model_spec) <- Shared.model_spec(client, request),
         opts <- Shared.request_opts(client, request),
         {:ok, result} <- call_generate_text(module, model_spec, Request.to_prompt(request), opts) do
      {:ok, Shared.response_from_result(result, client, request)}
    else
      nil -> {:error, Error.invalid(:model, "ReqLlmNext model is required")}
      {:error, reason} -> {:error, Shared.normalize_error(reason, adapter: __MODULE__)}
    end
  end

  @impl true
  def stream(%Client{} = _client, %Request{} = _request) do
    {:error, Error.unsupported_capability(:stream, adapter: __MODULE__)}
  end

  defp call_generate_text(module, model_spec, prompt, opts) do
    if function_exported?(module, :generate_text, 3) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(module, :generate_text, [model_spec, prompt, opts])
    else
      {:error, Error.missing_dependency(module, function: :generate_text)}
    end
  end
end
