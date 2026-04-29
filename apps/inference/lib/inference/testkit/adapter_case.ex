defmodule Inference.Testkit.AdapterCase do
  @moduledoc """
  Conformance helpers for adapter tests.
  """

  alias Inference.{Client, Error, Request, Response}

  @spec assert_text_completion(module(), keyword()) :: Response.t()
  def assert_text_completion(adapter, opts \\ []) do
    client =
      Client.new!(
        adapter: adapter,
        provider: Keyword.get(opts, :provider, :test),
        model: Keyword.get(opts, :model, "test-model"),
        adapter_opts: Keyword.get(opts, :adapter_opts, [])
      )

    request = Request.from_prompt!("hello")

    case adapter.complete(client, request) do
      {:ok, %Response{} = response} ->
        if Response.text(response) == "" do
          raise ArgumentError, "adapter returned an empty text response"
        end

        response

      other ->
        raise ArgumentError, "expected successful text completion, got: #{inspect(other)}"
    end
  end

  @spec assert_provider_error({:error, Error.t()}) :: Error.t()
  def assert_provider_error({:error, %Error{} = error}) do
    allowed = [
      :provider_error,
      :missing_dependency,
      :missing_credentials,
      :unsupported_capability,
      :adapter_exception,
      :invalid
    ]

    if error.category not in allowed do
      raise ArgumentError, "unexpected provider error category: #{inspect(error.category)}"
    end

    error
  end

  @spec assert_unsupported_stream(module(), keyword()) :: Error.t()
  def assert_unsupported_stream(adapter, opts \\ []) do
    client =
      Client.new!(
        adapter: adapter,
        provider: Keyword.get(opts, :provider, :test),
        model: Keyword.get(opts, :model, "test-model"),
        adapter_opts: Keyword.get(opts, :adapter_opts, [])
      )

    request = Request.from_prompt!("hello")

    case adapter.stream(client, request) do
      {:error, %Error{category: :unsupported_capability} = error} ->
        error

      other ->
        raise ArgumentError, "expected unsupported stream error, got: #{inspect(other)}"
    end
  end

  @spec assert_redacts_metadata(map()) :: map()
  def assert_redacts_metadata(metadata) do
    redacted = Inference.Redaction.redact(metadata)

    if inspect(redacted) =~ "secret" do
      raise ArgumentError, "metadata was not redacted"
    end

    redacted
  end

  @spec assert_trace_metadata(Response.t()) :: map()
  def assert_trace_metadata(%Response{trace: trace}) do
    Inference.Trace.redact(trace)
  end
end
