Mix.install([
  {:inference, path: Path.expand("../apps/inference", __DIR__)},
  {:req_llm_next, path: Path.expand("../../reqllm_next", __DIR__)}
])

provider =
  System.get_env("INFERENCE_REQLLM_NEXT_PROVIDER", "google")
  |> String.to_atom()

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
