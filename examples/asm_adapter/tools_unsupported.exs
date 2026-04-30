Mix.install([
  {:inference, path: Path.expand("../../apps/inference", __DIR__)},
  {:agent_session_manager, path: Path.expand("../../../agent_session_manager", __DIR__)}
])

defmodule InferenceExamples.ASMToolsUnsupported do
  @moduledoc false

  @switches [
    model: :string,
    provider: :string
  ]

  def main(argv) do
    {opts, _args, invalid} = OptionParser.parse(argv, strict: @switches)
    reject_invalid!(invalid)

    provider = opts |> required!(:provider) |> String.to_atom()
    model = required!(opts, :model)

    client =
      Inference.Client.new!(
        adapter: Inference.Adapters.ASM,
        provider: provider,
        model: model,
        defaults: [lane: :auto]
      )

    case Inference.complete(client, "Use the lookup tool.", options: [tools: [%{name: "lookup"}]]) do
      {:error, %Inference.Error{category: :unsupported_capability} = error} ->
        IO.puts("unsupported_as_expected=true")
        IO.puts("message=#{Exception.message(error)}")

      {:ok, response} ->
        IO.puts(:stderr, "Expected unsupported tools, got response: #{inspect(response)}")
        System.halt(1)

      {:error, error} ->
        IO.puts(:stderr, "Expected unsupported-capability error, got: #{Exception.message(error)}")
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
end

InferenceExamples.ASMToolsUnsupported.main(System.argv())
