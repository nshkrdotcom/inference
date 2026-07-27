defmodule Elixir.ASM.Error do
  @moduledoc false
  # Hand-written stand-in for the real `ASM.Error` struct in
  # `/home/home/p/g/n/agent_session_manager/lib/asm/error.ex`. This package
  # declares no provider dependency, so the adapter must classify the struct
  # structurally.

  @enforce_keys [:kind, :domain, :message]
  defexception [:kind, :domain, :message, :cause, :provider, :exit_code, :retryable, :recovery]

  @impl true
  def message(%__MODULE__{domain: domain, kind: kind, message: message}),
    do: "[#{domain}/#{kind}] #{message}"
end

defmodule Inference.Adapters.ASMTest do
  use ExUnit.Case, async: true

  alias Inference.Adapters.ASM, as: ASMAdapter
  alias Inference.{Capability, Client, Error}

  defmodule FakeResult do
    @moduledoc false
    defstruct [
      :text,
      :object,
      :tool_calls,
      :run_id,
      :session_id,
      :usage,
      :finish_reason,
      :metadata
    ]
  end

  defmodule FakeASM do
    @moduledoc false

    def query(target, prompt, opts) do
      send(self(), {:asm_query, target, prompt, opts})

      case Keyword.get(opts, :fail_with) do
        nil ->
          {:ok,
           %FakeResult{
             text: "asm reply",
             object: Keyword.get(opts, :reply_object),
             tool_calls: Keyword.get(opts, :reply_tool_calls),
             run_id: "run-1",
             session_id: "session-1",
             metadata: %{opts: opts}
           }}

        reason ->
          {:error, reason}
      end
    end

    def start_session(opts) do
      send(self(), {:asm_start_session, opts})
      {:ok, self()}
    end

    def stream(_session, _prompt, opts) do
      send(self(), {:asm_stream, opts})
      [%{text: "delta"}]
    end

    def stop_session(_session), do: :ok
  end

  defmodule RejectingOptions do
    @moduledoc false

    def preflight(provider, opts, preflight_opts) do
      send(self(), {:asm_preflight, provider, opts, preflight_opts})
      {:error, Inference.Error.invalid(:asm_options, "strict preflight rejected everything")}
    end
  end

  defmodule FakeProviderFeatures do
    @moduledoc false

    @providers [:amp, :antigravity, :claude, :codex, :cursor]
    @completion_supported [:claude, :codex]

    def common_feature(provider, :completion_only) when provider in @providers do
      {:ok,
       %{
         supported?: provider in @completion_supported,
         activation: %{option: :completion_only, value: true}
       }}
    end

    def common_feature(provider, :structured_output)
        when provider in @completion_supported do
      {:ok,
       %{
         supported?: true,
         activation: %{option: :output_schema},
         compatibility: %{wire_form: :inline_json, cli_flag: "--json-schema"}
       }}
    end

    def common_feature(provider, :structured_output) when provider in @providers,
      do: {:ok, %{supported?: false}}

    def common_feature(provider, feature) do
      {:error,
       Inference.Error.invalid(
         :unknown_common_feature,
         "unknown common feature #{inspect(feature)} for #{inspect(provider)}"
       )}
    end
  end

  defp client(opts \\ []) do
    Client.agent_session!(
      adapter: ASMAdapter,
      provider: Keyword.get(opts, :provider, :claude),
      model: "claude-model",
      adapter_opts: Keyword.merge([asm_module: FakeASM], Keyword.get(opts, :adapter_opts, []))
    )
  end

  describe "INF-1 the strict-common preflight is gone" do
    test "a completion never calls ASM.Options.preflight/3" do
      client = client(adapter_opts: [asm_options_module: RejectingOptions])

      assert {:ok, response} = Inference.complete(client, "hello")
      assert response.text == "asm reply"
      refute_received {:asm_preflight, _provider, _opts, _preflight_opts}
    end

    test "a custom ASM module no longer needs an explicit options module" do
      assert {:ok, _response} = Inference.complete(client(), "hello")
      assert_received {:asm_query, :claude, "user: hello", _opts}
    end

    test "provider-native options ASM itself validates are forwarded, not pre-rejected" do
      client = client(adapter_opts: [query_opts: [system_prompt: "be terse"]])

      assert {:ok, _response} = Inference.complete(client, "hello")
      assert_received {:asm_query, :claude, _prompt, opts}
      assert opts[:system_prompt] == "be terse"
    end
  end

  describe "INF-3 response_format mapping" do
    test "a json schema response format becomes ASM's output_schema option" do
      schema = %{"type" => "object", "properties" => %{"answer" => %{"type" => "string"}}}

      assert {:ok, _response} =
               Inference.complete(client(), "hello",
                 response_format: {:json_schema, %{name: "answer", schema: schema}}
               )

      assert_received {:asm_query, :claude, _prompt, opts}
      assert opts[:output_schema] == schema
    end

    test "the mapped schema wins over an adapter-supplied output_schema" do
      schema = %{"type" => "object"}

      client = client(adapter_opts: [query_opts: [output_schema: %{"type" => "string"}]])

      assert {:ok, _response} =
               Inference.complete(client, "hello",
                 response_format: {:json_schema, %{name: "answer", schema: schema}}
               )

      assert_received {:asm_query, :claude, _prompt, opts}
      assert opts[:output_schema] == schema
    end

    test "an ASM-reported object is propagated onto the response" do
      client = client(adapter_opts: [query_opts: [reply_object: %{"answer" => "42"}]])

      assert {:ok, response} =
               Inference.complete(client, "hello",
                 response_format: {:json_schema, %{name: "answer", schema: %{"type" => "object"}}}
               )

      assert response.object == %{"answer" => "42"}
    end

    test "schemaless json object mode is refused instead of dropped" do
      assert {:error, %Error{reason: :response_format_unsupported} = error} =
               Inference.complete(client(), "hello", response_format: {:json, :object})

      assert error.category == :unsupported_capability
      assert error.metadata.response_format == {:json, :object}
      refute_received {:asm_query, _target, _prompt, _opts}
    end

    test "a keyword schema is refused because ASM takes a JSON Schema map" do
      assert {:error, %Error{reason: :response_format_unsupported}} =
               Inference.complete(client(), "hello",
                 response_format:
                   {:json_schema, %{name: "answer", schema: [answer: [type: :string]]}}
               )

      refute_received {:asm_query, _target, _prompt, _opts}
    end

    test "an explicit text response format needs no provider option" do
      assert {:ok, _response} = Inference.complete(client(), "hello", response_format: :text)
      assert_received {:asm_query, :claude, _prompt, opts}
      refute Keyword.has_key?(opts, :output_schema)
    end
  end

  describe "INF-7 completion-only profile" do
    test "queries lock the completion-only provider profile" do
      assert {:ok, _response} = Inference.complete(client(), "hello")
      assert_received {:asm_query, :claude, _prompt, opts}
      assert opts[:completion_only] == true
    end

    test "a caller cannot unlock the completion-only profile" do
      client = client(adapter_opts: [query_opts: [completion_only: false]])

      assert {:ok, _response} = Inference.complete(client, "hello")
      assert_received {:asm_query, :claude, _prompt, opts}
      assert opts[:completion_only] == true
    end

    test "streams lock the completion-only profile too" do
      assert {:ok, stream} = Inference.stream(client(), "hello")
      assert Enum.map(stream, & &1.data) == ["delta"]
      assert_received {:asm_stream, opts}
      assert opts[:completion_only] == true
    end

    test "known unsupported providers fail before query dispatch" do
      for provider <- [:amp, :antigravity, :cursor] do
        client =
          client(
            provider: provider,
            adapter_opts: [asm_provider_features_module: FakeProviderFeatures]
          )

        assert {:error,
                %Error{
                  category: :unsupported_capability,
                  reason: :unsupported_capability
                } = error} = Inference.complete(client, "hello")

        assert error.metadata.provider == provider
        assert error.metadata.adapter == ASMAdapter
        refute_received {:asm_query, _target, _prompt, _opts}
      end
    end

    test "known unsupported providers fail before stream dispatch" do
      for provider <- [:amp, :antigravity, :cursor] do
        client =
          client(
            provider: provider,
            adapter_opts: [asm_provider_features_module: FakeProviderFeatures]
          )

        assert {:error,
                %Error{
                  category: :unsupported_capability,
                  reason: :unsupported_capability
                } = error} = Inference.stream(client, "hello")

        assert error.metadata.provider == provider
        refute_received {:asm_start_session, _opts}
        refute_received {:asm_stream, _opts}
      end
    end

    test "a returned tool call is a typed contract failure" do
      client =
        client(adapter_opts: [query_opts: [reply_tool_calls: [%{name: "lookup", id: "call-1"}]]])

      assert {:error, %Error{category: :invalid_response, reason: :unexpected_tool_call} = error} =
               Inference.complete(client, "hello")

      assert error.metadata.tool_calls == [%{name: "lookup", id: "call-1"}]
    end
  end

  describe "INF-4 provider error mapping" do
    test "ASM error kinds map onto the declared categories" do
      for {kind, domain, category} <- [
            {:timeout, :transport, :timeout},
            {:rate_limit, :provider, :rate_limited},
            {:auth_error, :provider, :missing_credentials},
            {:cli_not_found, :config, :missing_dependency},
            {:config_invalid, :config, :invalid},
            {:json_decode_error, :parser, :invalid_response},
            {:transport_error, :transport, :provider_error}
          ] do
        asm_error = %ASM.Error{
          kind: kind,
          domain: domain,
          message: "boom",
          provider: :claude,
          retryable: true
        }

        client = client(adapter_opts: [query_opts: [fail_with: asm_error]])

        assert {:error, %Error{} = error} = Inference.complete(client, "hello")

        assert error.category == category,
               "expected #{inspect(kind)} to map to #{inspect(category)}, got #{inspect(error.category)}"

        assert error.reason == kind
        assert error.metadata.provider_error == asm_error
        assert error.metadata.provider_error_domain == domain
        assert error.message =~ "boom"
      end
    end

    test "an unknown provider error struct is preserved instead of collapsed" do
      failure = %FakeResult{text: "not an error"}
      client = client(adapter_opts: [query_opts: [fail_with: failure]])

      assert {:error, %Error{category: :provider_error} = error} =
               Inference.complete(client, "hello")

      assert error.metadata.provider_error == failure
    end
  end

  describe "INF-5 capabilities" do
    test "structured output support is read from ASM's provider features" do
      client =
        client(
          provider: :claude,
          adapter_opts: [asm_provider_features_module: FakeProviderFeatures]
        )

      capabilities = Inference.capabilities(client)

      assert %Capability{support: :supported, metadata: metadata} =
               Capability.fetch!(capabilities, :response_format_json_schema)

      assert metadata.asm_option == :output_schema
      assert Capability.supported?(capabilities, :response_format_json_schema)
    end

    test "a provider that declares the feature unsupported reports unsupported" do
      client =
        client(
          provider: :antigravity,
          adapter_opts: [asm_provider_features_module: FakeProviderFeatures]
        )

      assert %Capability{support: :unsupported} =
               client
               |> Inference.capabilities()
               |> Capability.fetch!(:response_format_json_schema)
    end

    test "all five ASM providers report total completion-dependent capabilities" do
      for provider <- [:amp, :antigravity, :claude, :codex, :cursor] do
        client =
          client(
            provider: provider,
            adapter_opts: [asm_provider_features_module: FakeProviderFeatures]
          )

        capabilities = Inference.capabilities(client)
        expected = if provider in [:claude, :codex], do: :supported, else: :unsupported

        for capability <- [:completion_only, :response_format_text, :streaming] do
          assert %Capability{support: ^expected, metadata: metadata} =
                   Capability.fetch!(capabilities, capability)

          assert metadata.provider == provider
        end
      end
    end

    test "all five ASM providers report total structured-output capabilities" do
      for provider <- [:amp, :antigravity, :claude, :codex, :cursor] do
        client =
          client(
            provider: provider,
            adapter_opts: [asm_provider_features_module: FakeProviderFeatures]
          )

        expected = if provider in [:claude, :codex], do: :supported, else: :unsupported

        assert %Capability{support: ^expected} =
                 client
                 |> Inference.capabilities()
                 |> Capability.fetch!(:response_format_json_schema)
      end
    end

    test "a provider without a declared feature is unknown, never assumed supported" do
      client =
        client(
          provider: :unknown_provider,
          adapter_opts: [asm_provider_features_module: FakeProviderFeatures]
        )

      capabilities = Inference.capabilities(client)

      for capability <- [
            :completion_only,
            :response_format_text,
            :response_format_json_schema,
            :streaming
          ] do
        assert %Capability{support: :unknown} = Capability.fetch!(capabilities, capability)
      end

      refute Capability.supported?(capabilities, :response_format_json_schema)
    end

    test "an absent ASM feature module is unknown, never assumed supported" do
      capabilities = Inference.capabilities(client(provider: :claude))

      for capability <- [
            :completion_only,
            :response_format_text,
            :response_format_json_schema,
            :streaming
          ] do
        assert %Capability{support: :unknown} = Capability.fetch!(capabilities, capability)
      end
    end

    test "the completion-only profile is reported as an unsupported tool capability" do
      capabilities = Inference.capabilities(client())

      assert %Capability{support: :unsupported} = Capability.fetch!(capabilities, :tools)
      refute Capability.supported?(capabilities, :response_format_json_object)
    end
  end
end
