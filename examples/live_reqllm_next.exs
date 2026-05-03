Mix.install([
  {:inference, path: Path.expand("../apps/inference", __DIR__)},
  {:req_llm_next, path: Path.expand("../../reqllm_next", __DIR__)}
])

defmodule InferenceExamples.LiveReqLlmNext do
  @moduledoc false

  @providers %{
    "anthropic" => :anthropic,
    "gemini" => :gemini,
    "google" => :google,
    "ollama" => :ollama,
    "openai" => :openai
  }

  def main do
    provider = provider!(System.get_env("INFERENCE_REQLLM_NEXT_PROVIDER", "google"))
    model = System.get_env("INFERENCE_REQLLM_NEXT_MODEL", "gemini-3.1-flash-lite-preview")
    prompt = System.get_env("INFERENCE_REQLLM_NEXT_PROMPT", "Say hello from ReqLlmNext.")

    client =
      Inference.Client.new!(
        adapter: Inference.Adapters.ReqLlmNext,
        provider: provider,
        model: model
      )

    case Inference.complete(client, prompt) do
      {:ok, response} ->
        IO.puts(Inference.Response.text(response))

      {:error, error} ->
        IO.puts("ReqLlmNext example failed: #{Exception.message(error)}")
        IO.inspect(error.metadata, label: "metadata")
        System.halt(1)
    end
  end

  defp provider!(value) do
    case Map.fetch(@providers, value) do
      {:ok, provider} ->
        provider

      :error ->
        IO.puts(:stderr, "INFERENCE_REQLLM_NEXT_PROVIDER has unsupported value #{inspect(value)}")
        System.halt(64)
    end
  end
end

InferenceExamples.LiveReqLlmNext.main()
