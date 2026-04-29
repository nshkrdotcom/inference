Mix.install([
  {:inference, path: Path.expand("../apps/inference", __DIR__)},
  {:agent_session_manager, path: Path.expand("../../agent_session_manager", __DIR__)}
])

provider =
  System.get_env("INFERENCE_ASM_PROVIDER", "gemini")
  |> String.to_atom()

prompt = System.get_env("INFERENCE_ASM_PROMPT", "Say hello from Agent Session Manager.")

client =
  Inference.Client.new!(
    adapter: Inference.Adapters.ASM,
    provider: provider,
    model: System.get_env("INFERENCE_ASM_MODEL", "gemini-3.1-flash-lite-preview"),
    defaults: [
      lane: System.get_env("INFERENCE_ASM_LANE", "auto") |> String.to_atom()
    ]
  )

case Inference.complete(client, prompt) do
  {:ok, response} ->
    IO.puts(Inference.Response.text(response))
    IO.inspect(response.metadata, label: "metadata")

  {:error, error} ->
    IO.puts("ASM example failed: #{Exception.message(error)}")
    IO.inspect(error.metadata, label: "metadata")
    System.halt(1)
end
