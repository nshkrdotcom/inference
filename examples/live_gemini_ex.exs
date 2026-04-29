unless System.get_env("INFERENCE_LIVE_EXAMPLES") == "1" do
  IO.puts("live example disabled; set INFERENCE_LIVE_EXAMPLES=1 to run")
  System.halt(0)
end

Mix.install([
  {:inference, path: Path.expand("../apps/inference", __DIR__)},
  {:gemini, path: Path.expand("../../gemini_ex", __DIR__)}
])

api_key = System.fetch_env!("GEMINI_API_KEY")
model = System.get_env("INFERENCE_GEMINI_MODEL", "gemini-2.0-flash")

prompt =
  System.get_env("INFERENCE_GEMINI_PROMPT", "Say hello from GeminiEx in one short sentence.")

:ok = Gemini.configure(:gemini, %{api_key: api_key})

client =
  Inference.Client.new!(
    adapter: Inference.Adapters.GeminiEx,
    provider: :gemini,
    model: model
  )

case Inference.complete(client, prompt) do
  {:ok, response} ->
    IO.puts(Inference.Response.text(response))

  {:error, error} ->
    IO.puts("GeminiEx example failed: #{Exception.message(error)}")
    IO.inspect(error.metadata, label: "metadata")
    System.halt(1)
end
