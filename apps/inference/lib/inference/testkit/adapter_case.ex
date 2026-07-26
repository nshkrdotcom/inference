defmodule Inference.Testkit.AdapterCase do
  @moduledoc """
  Conformance helpers for adapter tests.
  """

  alias Inference.{Capability, Client, Error, Request, Response}

  @conformance_response_formats [
    :text,
    {:json, :object},
    {:json_schema, %{name: "conformance", schema: %{"type" => "object"}, strict: true}}
  ]

  @spec assert_text_completion(module(), keyword()) :: Response.t()
  def assert_text_completion(adapter, opts \\ []) do
    client = build_client(adapter, opts)
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

  @doc """
  Asserts an adapter honors the closed response-format union.

  For every format the adapter must either return a response (it mapped the
  format onto a real provider option) or refuse with a typed
  `:response_format_unsupported` 2-tuple. Silently dropping a declared format —
  the historical bug — is a conformance failure.
  """
  @spec assert_response_format_contract(module(), keyword()) :: :ok
  def assert_response_format_contract(adapter, opts \\ []) do
    client = build_client(adapter, opts)
    formats = Keyword.get(opts, :response_formats, @conformance_response_formats)

    Enum.each(formats, fn response_format ->
      request = Request.from_prompt!("hello", response_format: response_format)

      case adapter.complete(client, request) do
        {:ok, %Response{}} ->
          :ok

        {:error, %Error{reason: :response_format_unsupported}} ->
          :ok

        other ->
          raise ArgumentError,
                "adapter neither mapped nor refused #{inspect(response_format)}: #{inspect(other)}"
      end
    end)
  end

  @doc """
  Asserts an adapter reports well-formed capabilities before dispatch.

  `:require` names capabilities the adapter must report at all; a registry can
  then read the claim instead of dispatching to find out.
  """
  @spec assert_capability_contract(module(), keyword()) :: [Capability.t()]
  def assert_capability_contract(adapter, opts \\ []) do
    capabilities = adapter |> build_client(opts) |> Inference.capabilities()

    Enum.each(capabilities, fn capability ->
      unless is_struct(capability, Capability) and is_atom(capability.name) and
               capability.support in Capability.supports() do
        raise ArgumentError, "malformed capability: #{inspect(capability)}"
      end
    end)

    names = Enum.map(capabilities, & &1.name)

    if length(Enum.uniq(names)) != length(names) do
      raise ArgumentError, "duplicate capability names: #{inspect(names)}"
    end

    Enum.each(Keyword.get(opts, :require, []), fn name ->
      if name not in names do
        raise ArgumentError, "adapter does not report capability #{inspect(name)}"
      end
    end)

    capabilities
  end

  @spec assert_unsupported_stream(module(), keyword()) :: Error.t()
  def assert_unsupported_stream(adapter, opts \\ []) do
    client = build_client(adapter, opts)
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

  defp build_client(adapter, opts) do
    attrs = [
      adapter: adapter,
      provider: Keyword.get(opts, :provider, :test),
      model: Keyword.get(opts, :model, "test-model"),
      defaults: Keyword.get(opts, :defaults, []),
      adapter_opts: Keyword.get(opts, :adapter_opts, [])
    ]

    case Keyword.fetch(opts, :admitted_kinds) do
      {:ok, admitted_kinds} -> Client.new!(Keyword.put(attrs, :admitted_kinds, admitted_kinds))
      :error -> Client.new!(attrs)
    end
  end
end
