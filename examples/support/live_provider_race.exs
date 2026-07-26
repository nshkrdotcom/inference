defmodule InferenceExamples.LiveProviderRace do
  @moduledoc false

  @default_timeout_ms 180_000

  def run!(mode) when mode in [:text, :structured] do
    configure_gemini!()

    started_at = System.monotonic_time(:millisecond)

    {successes, failures} =
      providers()
      |> Task.async_stream(&complete(&1, mode),
        max_concurrency: 3,
        ordered: false,
        timeout: timeout_ms() + 10_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce({[], []}, fn result, {successes, failures} ->
        case result do
          {:ok, {:ok, provider, response, elapsed_ms}} ->
            rank = length(successes) + 1
            print_success(rank, provider, response, elapsed_ms, mode)
            {[provider | successes], failures}

          {:ok, {:error, provider, error, elapsed_ms}} ->
            print_failure(provider, error, elapsed_ms)
            {successes, [provider | failures]}

          {:exit, reason} ->
            IO.puts(:stderr, "[race] task exited: #{inspect(reason)}")
            {successes, [:task | failures]}
        end
      end)

    total_ms = System.monotonic_time(:millisecond) - started_at
    IO.puts("[race] completed in #{total_ms}ms")

    if failures != [] or length(successes) != 3 do
      System.halt(1)
    end
  end

  defp providers do
    [
      %{
        name: :gemini,
        client:
          Inference.Client.new!(
            adapter: Inference.Adapters.GeminiEx,
            provider: :gemini,
            model:
              System.get_env(
                "INFERENCE_RACE_GEMINI_MODEL",
                "gemini-3.1-flash-lite-preview"
              )
          )
      },
      %{
        name: :claude,
        client:
          Inference.Client.agent_session!(
            adapter: Inference.Adapters.ASM,
            provider: :claude,
            model: System.get_env("INFERENCE_RACE_CLAUDE_MODEL", "claude-opus-5"),
            defaults: [lane: :sdk, run_deadline_ms: timeout_ms()]
          )
      },
      %{
        name: :codex,
        client:
          Inference.Client.agent_session!(
            adapter: Inference.Adapters.ASM,
            provider: :codex,
            model: System.get_env("INFERENCE_RACE_CODEX_MODEL", "gpt-5.4"),
            defaults: [lane: :sdk, run_deadline_ms: timeout_ms()]
          )
      }
    ]
  end

  defp configure_gemini! do
    api_key = System.fetch_env!("GEMINI_API_KEY")
    :ok = Gemini.configure(:gemini, %{api_key: api_key})
  end

  defp complete(%{name: provider, client: client}, mode) do
    started_at = System.monotonic_time(:millisecond)

    result =
      case mode do
        :text ->
          Inference.complete(client, "Reply with exactly: hello", max_tokens: 8)

        :structured ->
          Inference.complete(
            client,
            "Return the required JSON object. Set message to hello.",
            max_tokens: 32,
            response_format: response_format()
          )
      end

    elapsed_ms = System.monotonic_time(:millisecond) - started_at

    case result do
      {:ok, response} -> validate_response(provider, response, elapsed_ms, mode)
      {:error, error} -> {:error, provider, error, elapsed_ms}
    end
  end

  defp validate_response(provider, response, elapsed_ms, :text) do
    if String.contains?(String.downcase(Inference.Response.text(response)), "hello") do
      {:ok, provider, response, elapsed_ms}
    else
      {:error, provider, "response did not contain hello", elapsed_ms}
    end
  end

  defp validate_response(provider, %{object: object} = response, elapsed_ms, :structured)
       when is_map(object) do
    message = Map.get(object, "message") || Map.get(object, :message)

    if message == "hello" do
      {:ok, provider, response, elapsed_ms}
    else
      {:error, provider, "structured response did not contain message=hello", elapsed_ms}
    end
  end

  defp validate_response(provider, response, elapsed_ms, :structured) do
    detail = %{
      text: Inference.Response.text(response),
      raw_type: raw_type(response.raw),
      metadata: Map.take(response.metadata, [:duration_ms, :lane, :model_version])
    }

    {:error, provider, "provider returned no structured object: #{inspect(detail)}", elapsed_ms}
  end

  defp response_format do
    {:json_schema,
     %{
       name: "hello_response",
       strict: true,
       schema: %{
         "type" => "object",
         "additionalProperties" => false,
         "properties" => %{
           "message" => %{"type" => "string", "enum" => ["hello"]}
         },
         "required" => ["message"]
       }
     }}
  end

  defp print_success(rank, provider, response, elapsed_ms, :text) do
    IO.puts(
      "[#{rank}] #{provider} #{elapsed_ms}ms: #{String.trim(Inference.Response.text(response))}"
    )
  end

  defp print_success(rank, provider, response, elapsed_ms, :structured) do
    IO.puts("[#{rank}] #{provider} #{elapsed_ms}ms: #{inspect(response.object)}")
  end

  defp print_failure(provider, error, elapsed_ms) do
    IO.puts(:stderr, "[race] #{provider} failed after #{elapsed_ms}ms: #{error_message(error)}")
  end

  defp error_message(%{__exception__: true} = error), do: Exception.message(error)
  defp error_message(error) when is_binary(error), do: error
  defp error_message(error), do: inspect(error)

  defp raw_type(%{__struct__: module}), do: module
  defp raw_type(raw) when is_map(raw), do: :map
  defp raw_type(raw) when is_binary(raw), do: :binary
  defp raw_type(nil), do: nil
  defp raw_type(_raw), do: :other

  defp timeout_ms do
    case Integer.parse(System.get_env("INFERENCE_RACE_TIMEOUT_MS", "")) do
      {value, ""} when value > 0 -> value
      _other -> @default_timeout_ms
    end
  end
end
