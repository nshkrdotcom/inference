req_llm_path = System.get_env("INFERENCE_REQ_LLM_PATH")

if is_nil(req_llm_path) do
  IO.puts("""
  ReqLLM live example requires INFERENCE_REQ_LLM_PATH to point at a local req_llm checkout.

      export INFERENCE_REQ_LLM_PATH=/path/to/req_llm
      elixir examples/live_req_llm.exs
  """)

  System.halt(1)
end

Mix.install([
  {:inference, path: Path.expand("../apps/inference", __DIR__)},
  {:req_llm, path: Path.expand(req_llm_path)}
])

provider =
  System.get_env("INFERENCE_REQ_LLM_PROVIDER", "gemini")
  |> String.to_atom()

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
