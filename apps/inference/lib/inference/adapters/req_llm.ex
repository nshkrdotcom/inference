defmodule Inference.Adapters.ReqLLM do
  @moduledoc """
  Compatibility adapter for existing ReqLLM-style clients.
  """

  @behaviour Inference.Adapter

  alias Inference.Adapters.Shared
  alias Inference.{Client, Error, Request}

  @impl true
  def complete(%Client{} = client, %Request{} = request) do
    module = Keyword.get(client.adapter_opts, :req_llm_module, ReqLLM)

    with :ok <- Shared.ensure_dependency(module),
         model_spec when not is_nil(model_spec) <- model_spec(client, request),
         opts <- request_opts(client, request),
         {:ok, result} <- call_generate_text(module, model_spec, Request.to_prompt(request), opts) do
      {:ok, Shared.response_from_result(result, client, request)}
    else
      nil -> {:error, Error.invalid(:model, "ReqLLM model is required")}
      {:error, reason} -> {:error, Shared.normalize_error(reason, adapter: __MODULE__)}
    end
  end

  @impl true
  def stream(%Client{} = _client, %Request{} = _request) do
    {:error, Error.unsupported_capability(:stream, adapter: __MODULE__)}
  end

  defp model_spec(%Client{} = client, %Request{} = request) do
    Keyword.get(client.adapter_opts, :model_spec) ||
      %{provider: client.provider, id: request.model || client.model}
  end

  defp request_opts(%Client{} = client, %Request{} = request) do
    client
    |> Shared.request_opts(request)
    |> Keyword.delete(:model)
  end

  defp call_generate_text(module, model_spec, prompt, opts) do
    cond do
      function_exported?(module, :generate_text, 3) ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(module, :generate_text, [model_spec, prompt, opts])

      function_exported?(module, :generate, 3) ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(module, :generate, [model_spec, prompt, opts])

      true ->
        {:error, Error.missing_dependency(module, function: :generate_text)}
    end
  end
end
