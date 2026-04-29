unless System.get_env("INFERENCE_LIVE_EXAMPLES") == "1" do
  IO.puts("live example disabled; set INFERENCE_LIVE_EXAMPLES=1 to run")
  System.halt(0)
end

Mix.install([
  {:inference, path: Path.expand("../apps/inference", __DIR__)},
  {:agent_session_manager, path: Path.expand("../../agent_session_manager", __DIR__)}
])

provider =
  System.get_env("INFERENCE_ASM_PROVIDER", "codex")
  |> String.to_atom()

prompt = System.get_env("INFERENCE_ASM_PROMPT", "Say hello from Agent Session Manager.")

client =
  Inference.Client.new!(
    adapter: Inference.Adapters.ASM,
    provider: provider,
    model: System.get_env("INFERENCE_ASM_MODEL"),
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
