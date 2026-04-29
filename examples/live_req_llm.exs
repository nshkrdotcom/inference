unless System.get_env("INFERENCE_LIVE_EXAMPLES") == "1" do
  IO.puts("live example disabled; set INFERENCE_LIVE_EXAMPLES=1 to run")
  System.halt(0)
end

req_llm_path = System.get_env("INFERENCE_REQ_LLM_PATH")

if is_nil(req_llm_path) do
  IO.puts("""
  ReqLLM live example requires INFERENCE_REQ_LLM_PATH to point at a local req_llm checkout.

      export INFERENCE_REQ_LLM_PATH=/path/to/req_llm
      export INFERENCE_LIVE_EXAMPLES=1
      elixir examples/live_req_llm.exs
  """)

  System.halt(1)
end

Mix.install([
  {:inference, path: Path.expand("../apps/inference", __DIR__)},
  {:req_llm, path: Path.expand(req_llm_path)}
])

provider =
  System.get_env("INFERENCE_REQ_LLM_PROVIDER", "openai")
  |> String.to_atom()

model = System.get_env("INFERENCE_REQ_LLM_MODEL", "gpt-4o-mini")
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
