case {System.get_env("GOOGLE_API_KEY"), System.get_env("GEMINI_API_KEY")} do
  {nil, api_key} when is_binary(api_key) and api_key != "" ->
    System.put_env("GOOGLE_API_KEY", api_key)

  _ ->
    :ok
end

Mix.install([
  {:inference, path: Path.expand("../apps/inference", __DIR__)},
  {:req_llm, "~> 1.10"}
])

defmodule InferenceExamples.LiveReqLLM do
  @moduledoc false

  @providers %{
    "anthropic" => :anthropic,
    "gemini" => :gemini,
    "google" => :google,
    "openai" => :openai
  }

  def main do
    provider = provider!(System.get_env("INFERENCE_REQ_LLM_PROVIDER", "google"))
    model = System.get_env("INFERENCE_REQ_LLM_MODEL", "gemini-3.1-flash-lite-preview")
    prompt = System.get_env("INFERENCE_REQ_LLM_PROMPT", "Say hello from ReqLLM.")

    client =
      Inference.Client.new!(
        adapter: Inference.Adapters.ReqLLM,
        provider: provider,
        model: model
      )

    case Inference.complete(client, prompt) do
      {:ok, response} ->
        IO.puts(Inference.Response.text(response))

      {:error, error} ->
        IO.puts("ReqLLM example failed: #{Exception.message(error)}")
        IO.inspect(error.metadata, label: "metadata")
        System.halt(1)
    end
  end

  defp provider!(value) do
    case Map.fetch(@providers, value) do
      {:ok, provider} ->
        provider

      :error ->
        IO.puts(:stderr, "INFERENCE_REQ_LLM_PROVIDER has unsupported value #{inspect(value)}")
        System.halt(64)
    end
  end
end

InferenceExamples.LiveReqLLM.main()
