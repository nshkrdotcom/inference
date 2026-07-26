defmodule Inference.Adapters.ASM do
  @moduledoc """
  Adapter for Agent Session Manager.

  The consuming application must install and configure `:agent_session_manager`.

  ASM owns its own option contract: `ASM.Options.validate/2` is the run-path
  gate. This adapter does not re-impose ASM's strict-common preflight from the
  outside; it maps the provider-neutral request onto ASM options, locks the
  completion-only provider profile, and refuses tools it cannot honor.

  `{:json_schema, _}` response formats map onto ASM's `:output_schema` option.
  """

  @behaviour Inference.Adapter

  alias Inference.Adapters.Shared
  alias Inference.{Capability, Client, Error, Request, StreamEvent}

  @unadmitted_tool_keys [:tools, :tool_choice, :host_tools, :dynamic_tools, :allowed_tools]
  @tool_message_prefix "ASM adapter does not support inference tools or provider-native tool controls yet"

  # Bound at RUNTIME by module name: this package declares no provider
  # dependency, so ASM's feature manifest is consulted only when the consuming
  # application actually installs ASM.
  @asm_provider_features ASM.ProviderFeatures
  @structured_output_feature :structured_output

  @impl true
  def provider_kind, do: :agent_session

  @impl true
  def complete(%Client{} = client, %Request{} = request) do
    module = Keyword.get(client.adapter_opts, :asm_module, ASM)

    with :ok <- Shared.ensure_dependency(module),
         {:ok, opts} <- query_opts(client, request),
         {target, opts} <- query_target(client, request, opts),
         :ok <- validate_target(target),
         {:ok, result} <- call_query(module, target, prompt(request), opts),
         {:ok, result} <- reject_tool_calls(result) do
      {:ok,
       Shared.response_from_result(result, client, request, metadata: metadata(result, client))}
    else
      {:error, reason} -> {:error, Shared.normalize_error(reason, adapter: __MODULE__)}
    end
  end

  @impl true
  def stream(%Client{} = client, %Request{} = request) do
    module = Keyword.get(client.adapter_opts, :asm_module, ASM)

    with :ok <- Shared.ensure_dependency(module),
         {:ok, opts} <- stream_opts(client, request),
         {:ok, session, opts, ownership} <- stream_session(module, client, request, opts),
         {:ok, raw_stream} <- call_stream(module, session, prompt(request), opts) do
      {:ok,
       raw_stream
       |> maybe_close_after_stream(module, session, ownership)
       |> Stream.flat_map(&stream_events/1)}
    else
      {:error, reason} -> {:error, Shared.normalize_error(reason, adapter: __MODULE__)}
    end
  end

  @impl true
  def capabilities(%Client{} = client) do
    [
      Capability.new(:response_format_text, :supported),
      Capability.new(:response_format_json_object, :unsupported, %{
        message: "ASM structured output is schema-driven; there is no schemaless JSON mode"
      }),
      structured_output_capability(client),
      Capability.new(:tools, :unsupported, %{profile: :completion_only}),
      Capability.new(:streaming, :supported)
    ]
  end

  defp validate_target(nil),
    do: {:error, Error.invalid(:provider, "ASM provider or session is required")}

  defp validate_target(_target), do: :ok

  defp call_query(module, target, prompt, opts) do
    if function_exported?(module, :query, 3) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(module, :query, [target, prompt, opts])
    else
      {:error, Error.missing_dependency(module, function: :query)}
    end
  end

  defp query_target(%Client{} = client, %Request{} = request, opts) do
    case request.session || Keyword.get(client.adapter_opts, :session) do
      session when is_pid(session) ->
        {session, opts}

      session_id when is_binary(session_id) and session_id != "" ->
        {client.provider, Keyword.put(opts, :session_id, session_id)}

      _session ->
        {client.provider, opts}
    end
  end

  defp call_stream(module, session, prompt, opts) do
    if function_exported?(module, :stream, 3) do
      {:ok, module.stream(session, prompt, opts)}
    else
      {:error, Error.missing_dependency(module, function: :stream)}
    end
  end

  defp stream_session(module, %Client{} = client, %Request{} = request, opts) do
    case request.session || Keyword.get(client.adapter_opts, :session) do
      session when is_pid(session) ->
        {:ok, session, opts, :external}

      session_id when is_binary(session_id) and session_id != "" ->
        start_managed_stream_session(module, client, Keyword.put(opts, :session_id, session_id))

      _session ->
        start_managed_stream_session(module, client, opts)
    end
  end

  defp start_managed_stream_session(module, %Client{} = client, opts) do
    if function_exported?(module, :start_session, 1) do
      start_opts =
        opts
        |> Keyword.put_new(:provider, client.provider)
        |> Keyword.merge(Keyword.get(client.adapter_opts, :session_opts, []))

      stream_opts = Keyword.drop(opts, [:provider, :session_id, :name, :options])

      with {:ok, session} <- module.start_session(start_opts) do
        {:ok, session, stream_opts, :managed}
      end
    else
      {:error, Error.missing_dependency(module, function: :start_session)}
    end
  end

  defp maybe_close_after_stream(stream, module, session, :managed) do
    Stream.transform(
      stream,
      fn -> :ok end,
      fn event, acc -> {[event], acc} end,
      fn _acc ->
        if function_exported?(module, :stop_session, 1) do
          module.stop_session(session)
        end
      end
    )
  end

  defp maybe_close_after_stream(stream, _module, _session, :external), do: stream

  defp query_opts(%Client{} = client, %Request{} = request) do
    build_opts(client, request, Keyword.get(client.adapter_opts, :query_opts, []))
  end

  defp stream_opts(%Client{} = client, %Request{} = request) do
    build_opts(client, request, Keyword.get(client.adapter_opts, :stream_opts, []))
  end

  defp build_opts(%Client{} = client, %Request{} = request, adapter_opts) do
    opts =
      client
      |> Shared.request_opts(request)
      |> Keyword.drop([:temperature, :top_p, :max_tokens, :prompt])
      |> rename_timeout()
      |> Keyword.merge(adapter_opts)

    with :ok <-
           Shared.reject_tool_options(opts, @unadmitted_tool_keys,
             adapter: __MODULE__,
             message_prefix: @tool_message_prefix
           ),
         {:ok, format_opts} <- response_format_opts(request) do
      {:ok,
       opts
       |> Keyword.merge(format_opts)
       |> Keyword.put(:completion_only, true)}
    end
  end

  # ASM's structured output is schema-driven: the schema rides the provider's
  # own `:output_schema` option (inline JSON for Claude, a materialized file for
  # Codex). Anything ASM cannot express is refused, never dropped.
  defp response_format_opts(%Request{response_format: nil}), do: {:ok, []}
  defp response_format_opts(%Request{response_format: :text}), do: {:ok, []}

  defp response_format_opts(%Request{response_format: {:json_schema, %{schema: schema}}})
       when is_map(schema),
       do: {:ok, [output_schema: schema]}

  defp response_format_opts(%Request{response_format: {:json_schema, _spec} = response_format}) do
    {:error,
     Error.response_format_unsupported(response_format,
       adapter: __MODULE__,
       message: "ASM :output_schema takes a JSON Schema map"
     )}
  end

  defp response_format_opts(%Request{response_format: response_format}) do
    {:error,
     Error.response_format_unsupported(response_format,
       adapter: __MODULE__,
       message: "ASM has no schemaless JSON mode; declare a {:json_schema, _} response format"
     )}
  end

  defp reject_tool_calls(result) do
    Shared.reject_tool_calls(result, List.wrap(Shared.extract_field(result, :tool_calls)),
      adapter: __MODULE__
    )
  end

  defp structured_output_capability(%Client{provider: provider} = client) do
    case declared_structured_output(client, provider) do
      {:ok, %{supported?: true} = manifest} ->
        Capability.new(:response_format_json_schema, :supported, %{
          provider: provider,
          asm_option: :output_schema,
          provider_feature: manifest
        })

      {:ok, manifest} ->
        Capability.new(:response_format_json_schema, :unsupported, %{
          provider: provider,
          provider_feature: manifest
        })

      :undeclared ->
        Capability.new(:response_format_json_schema, :unknown, %{
          provider: provider,
          message: "ASM declares no #{inspect(@structured_output_feature)} feature here"
        })
    end
  end

  defp declared_structured_output(%Client{} = client, provider)
       when is_atom(provider) and not is_nil(provider) do
    module =
      Keyword.get(client.adapter_opts, :asm_provider_features_module, @asm_provider_features)

    if is_atom(module) and Code.ensure_loaded?(module) and
         function_exported?(module, :common_feature, 2) do
      read_structured_output(module, provider)
    else
      :undeclared
    end
  end

  defp declared_structured_output(%Client{}, _provider), do: :undeclared

  defp read_structured_output(module, provider) do
    case module.common_feature(provider, @structured_output_feature) do
      {:ok, %{supported?: supported?} = manifest} when is_boolean(supported?) -> {:ok, manifest}
      _other -> :undeclared
    end
  end

  defp rename_timeout(opts) do
    case Keyword.pop(opts, :timeout) do
      {nil, renamed} -> renamed
      {timeout, renamed} -> Keyword.put_new(renamed, :transport_timeout_ms, timeout)
    end
  end

  defp metadata(result, %Client{} = client) do
    result_metadata = Shared.extract_field(result, :metadata) || %{}

    Map.merge(result_metadata, %{
      run_id: Shared.extract_field(result, :run_id),
      session_id: Shared.extract_field(result, :session_id),
      session_id_from_cli: Shared.extract_field(result, :session_id_from_cli),
      cost: Shared.extract_field(result, :cost),
      duration_ms: Shared.extract_field(result, :duration_ms),
      lane: Keyword.get(client.defaults, :lane)
    })
  end

  defp stream_events(chunk) when is_binary(chunk), do: delta(chunk)

  defp stream_events(%{__struct__: module} = chunk) do
    text =
      if function_exported?(module, :assistant_text, 1) do
        module.assistant_text(chunk)
      else
        Shared.extract_text(chunk)
      end

    delta(text)
  end

  defp stream_events(chunk) when is_map(chunk), do: chunk |> Shared.extract_text() |> delta()
  defp stream_events(_chunk), do: []

  defp delta(text) when is_binary(text) and text != "",
    do: [%StreamEvent{type: :delta, data: text}]

  defp delta(_text), do: []

  defp prompt(%Request{options: options} = request) do
    Keyword.get(options, :prompt) || Request.to_prompt(request)
  end
end
