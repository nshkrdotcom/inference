Mix.install([
  {:inference, path: Path.expand("../../apps/inference", __DIR__)},
  {:agent_session_manager, path: Path.expand("../../../agent_session_manager", __DIR__)}
])

defmodule InferenceExamples.ASMTextOnly do
  @moduledoc false

  @switches [
    lane: :string,
    model: :string,
    prompt: :string,
    provider: :string
  ]

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

  def main(argv) do
    {opts, args, invalid} = OptionParser.parse(argv, strict: @switches)
    reject_invalid!(invalid)

    provider = opts |> required!(:provider) |> provider!()
    model = required!(opts, :model)
    prompt = Keyword.get(opts, :prompt) || Enum.join(args, " ")

    prompt =
      if String.trim(prompt) == "", do: "Reply with exactly: INFERENCE_ASM_OK", else: prompt

    lane = opts |> Keyword.get(:lane, "auto") |> lane!()

    client =
      Inference.Client.new!(
        adapter: Inference.Adapters.ASM,
        provider: provider,
        model: model,
        defaults: [lane: lane]
      )

    case Inference.complete(client, prompt) do
      {:ok, response} ->
        IO.puts(Inference.Response.text(response))
        IO.inspect(response.metadata, label: "metadata")

      {:error, error} ->
        IO.puts(:stderr, "Inference ASM text-only example failed: #{Exception.message(error)}")
        IO.inspect(error.metadata, label: "metadata")
        System.halt(1)
    end
  end

  defp reject_invalid!([]), do: :ok

  defp reject_invalid!(invalid) do
    raise ArgumentError, "invalid options: #{inspect(invalid)}"
  end

  defp required!(opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: missing_required!(key), else: value

      _other ->
        missing_required!(key)
    end
  end

  defp missing_required!(key) do
    IO.puts(:stderr, "Missing required --#{String.replace(to_string(key), "_", "-")}.")
    System.halt(64)
  end

  defp provider!(value), do: fetch_known!(@providers, value, "provider")
  defp lane!(value), do: fetch_known!(@lanes, value, "lane")

  defp fetch_known!(known, value, label) do
    case Map.fetch(known, value) do
      {:ok, parsed} ->
        parsed

      :error ->
        IO.puts(:stderr, "Unsupported #{label}: #{inspect(value)}")
        System.halt(64)
    end
  end
end

InferenceExamples.ASMTextOnly.main(System.argv())
