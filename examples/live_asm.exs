Mix.install([
  {:inference, path: Path.expand("../apps/inference", __DIR__)},
  {:agent_session_manager, path: Path.expand("../../agent_session_manager", __DIR__)}
])

defmodule InferenceExamples.LiveASM do
  @moduledoc false

  @providers %{
    "amp" => :amp,
    "anthropic" => :anthropic,
    "claude" => :claude,
    "codex" => :codex,
    "gemini" => :gemini,
    "google" => :google,
    "openai" => :openai
  }

  @lanes %{
    "auto" => :auto,
    "cli" => :cli,
    "core" => :core,
    "sdk" => :sdk
  }

  def main do
    provider = provider!(System.get_env("INFERENCE_ASM_PROVIDER", "gemini"))
    prompt = System.get_env("INFERENCE_ASM_PROMPT", "Say hello from Agent Session Manager.")

    client =
      Inference.Client.new!(
        adapter: Inference.Adapters.ASM,
        provider: provider,
        model: System.get_env("INFERENCE_ASM_MODEL", "gemini-3.1-flash-lite-preview"),
        defaults: [
          lane: lane!(System.get_env("INFERENCE_ASM_LANE", "auto"))
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
  end

  defp provider!(value), do: fetch_known!(@providers, value, "INFERENCE_ASM_PROVIDER")
  defp lane!(value), do: fetch_known!(@lanes, value, "INFERENCE_ASM_LANE")

  defp fetch_known!(known, value, label) do
    case Map.fetch(known, value) do
      {:ok, parsed} ->
        parsed

      :error ->
        IO.puts(:stderr, "#{label} has unsupported value #{inspect(value)}")
        System.halt(64)
    end
  end
end

InferenceExamples.LiveASM.main()
