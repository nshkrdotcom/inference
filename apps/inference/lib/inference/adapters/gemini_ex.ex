defmodule Inference.Adapters.GeminiEx do
  @moduledoc """
  Adapter for the owned `gemini_ex` SDK.
  """

  @behaviour Inference.Adapter

  alias Inference.Adapters.Shared
  alias Inference.{Client, Error, Request}

  @impl true
  def complete(%Client{} = client, %Request{} = request) do
    module = Keyword.get(client.adapter_opts, :gemini_module, Gemini)

    with :ok <- Shared.ensure_dependency(module),
         opts <- Shared.request_opts(client, request),
         {:ok, result} <- call_text(module, Request.user_prompt(request), opts) do
      {:ok, Shared.response_from_result(result, client, request, text: result)}
    else
      {:error, reason} -> {:error, Shared.normalize_error(reason, adapter: __MODULE__)}
    end
  end

  @impl true
  def stream(%Client{} = _client, %Request{} = _request) do
    {:error, Error.unsupported_capability(:stream, adapter: __MODULE__)}
  end

  defp call_text(module, prompt, opts) do
    cond do
      function_exported?(module, :text, 2) ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(module, :text, [prompt, opts])

      function_exported?(module, :generate, 2) ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(module, :generate, [prompt, opts])

      true ->
        {:error, Error.missing_dependency(module, function: :text)}
    end
  end
end
