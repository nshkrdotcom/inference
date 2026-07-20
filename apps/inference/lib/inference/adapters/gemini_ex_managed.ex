defmodule Inference.Adapters.GeminiExManaged do
  @moduledoc """
  Managed-materialization adapter for the owned `gemini_ex` SDK.

  Jido owns account selection, lease redemption, and construction of the
  transient `Gemini.GovernedAuthority`. This adapter verifies that the
  materialization and the client's durable-safe authority projection agree,
  then forwards unary and incremental provider semantics without consulting
  standalone or application-global Gemini configuration.
  """

  @behaviour Inference.Adapter

  alias Inference.{Client, Error, Request, Response, StreamEvent}

  @safe_authority_fields [
    :authority_ref,
    :execution_context_ref,
    :adapter_ref,
    :provider_ref,
    :provider_family,
    :connector_instance_ref,
    :connector_binding_ref,
    :endpoint_ref,
    :provider_account_ref,
    :credential_ref,
    :credential_handle_ref,
    :credential_lease_ref,
    :target_ref,
    :target_posture_ref,
    :attach_grant_ref,
    :operation_policy_ref,
    :model_ref,
    :model_account_ref,
    :service_identity_ref,
    :service_principal_ref,
    :tenant_id,
    :connection_id,
    :quota_scope_ref,
    :materialization_ref,
    :effect_ref,
    :operation_ref,
    :redaction_ref,
    :generation,
    :fence,
    :expires_at
  ]

  @required_client_authority_fields [
    :authority_ref,
    :execution_context_ref,
    :adapter_ref,
    :provider_ref,
    :provider_family,
    :connector_instance_ref,
    :connector_binding_ref,
    :endpoint_ref,
    :provider_account_ref,
    :credential_ref,
    :credential_handle_ref,
    :credential_lease_ref,
    :target_ref,
    :target_posture_ref,
    :attach_grant_ref,
    :operation_policy_ref,
    :model_ref,
    :model_account_ref,
    :service_identity_ref,
    :service_principal_ref,
    :tenant_id,
    :connection_id,
    :quota_scope_ref,
    :materialization_ref,
    :effect_ref,
    :operation_ref,
    :generation,
    :fence,
    :expires_at
  ]

  @allowed_generation_options [
    :model,
    :temperature,
    :top_p,
    :top_k,
    :max_tokens,
    :max_output_tokens,
    :timeout,
    :receive_timeout,
    :stop_sequences,
    :candidate_count,
    :seed,
    :thinking_config,
    :safety_settings,
    :system_instruction
  ]

  @default_receive_timeout 60_000

  @impl true
  def provider_kind, do: :model_endpoint

  @impl true
  def credential_mode, do: :managed_materialization

  @impl true
  def complete(%Client{} = client, %Request{} = request) do
    with {:ok, context} <- validate_context(client),
         {:ok, provider_opts, _receive_timeout} <- provider_opts(client, request),
         :ok <- ensure_provider_function(:generate, 2),
         {:ok, result} <- provider_call(:generate, [Request.user_prompt(request), provider_opts]),
         {:ok, response} <- normalize_response(result, client, request, context.refs) do
      {:ok, response}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, provider_error(reason)}
    end
  end

  @impl true
  def stream(%Client{} = client, %Request{} = request) do
    with {:ok, context} <- validate_context(client),
         {:ok, provider_opts, receive_timeout} <- provider_opts(client, request),
         :ok <- ensure_stream_provider() do
      {:ok,
       managed_stream(
         Request.user_prompt(request),
         provider_opts,
         receive_timeout,
         context.refs
       )}
    end
  end

  defp validate_context(%Client{} = client) do
    with :ok <- validate_provider_and_model(client),
         {:ok, authority} <- transient_authority(client.adapter_opts),
         {:ok, authority} <- validate_transient_authority(authority),
         {:ok, refs} <- authority_refs(authority),
         :ok <- validate_client_authority(client.authority, refs) do
      {:ok, %{authority: authority, refs: refs}}
    end
  end

  defp validate_provider_and_model(%Client{provider: :gemini, model: model})
       when is_binary(model) and model != "",
       do: :ok

  defp validate_provider_and_model(%Client{provider: provider, model: model}) do
    {:error,
     Error.invalid(
       :managed_gemini_client,
       "managed Gemini requires provider :gemini and an explicit model",
       provider: provider,
       model_present?: is_binary(model) and model != ""
     )}
  end

  defp transient_authority(governed_authority: authority) do
    if is_struct(authority, Gemini.GovernedAuthority) do
      {:ok, authority}
    else
      {:error,
       Error.invalid(
         :credential_materialization_required,
         "managed Gemini requires exactly one transient Gemini.GovernedAuthority"
       )}
    end
  end

  defp transient_authority(_adapter_opts) do
    {:error,
     Error.invalid(
       :credential_materialization_required,
       "managed Gemini requires exactly one transient Gemini.GovernedAuthority"
     )}
  end

  defp validate_transient_authority(authority) do
    with :ok <- ensure_provider_function(Gemini.GovernedAuthority, :new!, 1) do
      {:ok, apply(Gemini.GovernedAuthority, :new!, [authority])}
    end
  rescue
    error in ArgumentError ->
      {:error,
       Error.invalid(
         :invalid_credential_materialization,
         "managed Gemini credential materialization is invalid",
         cause: error.__struct__
       )}
  end

  defp authority_refs(authority) do
    with :ok <- ensure_provider_function(Gemini.GovernedAuthority, :refs, 1),
         refs when is_map(refs) <- apply(Gemini.GovernedAuthority, :refs, [authority]) do
      {:ok, refs}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      _other ->
        {:error,
         Error.invalid(
           :invalid_credential_materialization,
           "managed Gemini authority did not expose safe refs"
         )}
    end
  end

  defp validate_client_authority(authority, provider_refs) when is_map(authority) do
    unknown_fields = Map.keys(authority) -- @safe_authority_fields

    missing_fields =
      Enum.reject(@required_client_authority_fields, &present_authority_field?(authority, &1))

    mismatches =
      Enum.reduce(provider_refs, [], fn {field, expected}, acc ->
        if Map.get(authority, field) == expected, do: acc, else: [field | acc]
      end)

    cond do
      unknown_fields != [] ->
        {:error,
         Error.invalid(
           :unsafe_managed_authority,
           "managed Gemini client authority contains fields outside the safe projection",
           fields: Enum.sort(unknown_fields)
         )}

      missing_fields != [] ->
        {:error,
         Error.invalid(
           :managed_authority_missing_refs,
           "managed Gemini client authority is missing required refs",
           fields: missing_fields
         )}

      mismatches != [] ->
        {:error,
         Error.invalid(
           :managed_authority_mismatch,
           "managed Gemini client refs do not match the transient materialization",
           fields: Enum.sort(mismatches)
         )}

      Map.get(authority, :adapter_ref) != "gemini_ex" ->
        {:error,
         Error.invalid(
           :managed_adapter_mismatch,
           "managed Gemini authority requires the gemini_ex provider adapter ref"
         )}

      true ->
        :ok
    end
  end

  defp validate_client_authority(_authority, _provider_refs) do
    {:error,
     Error.invalid(
       :managed_authority_required,
       "managed Gemini requires a safe reference-only client authority"
     )}
  end

  defp present_authority_field?(authority, :generation) do
    case Map.get(authority, :generation) do
      value when is_integer(value) and value > 0 -> true
      _other -> false
    end
  end

  defp present_authority_field?(authority, :fence) do
    case Map.get(authority, :fence) do
      value when is_integer(value) and value >= 0 -> true
      _other -> false
    end
  end

  defp present_authority_field?(authority, :expires_at),
    do: is_struct(Map.get(authority, :expires_at), DateTime)

  defp present_authority_field?(authority, field) do
    case Map.get(authority, field) do
      value when is_binary(value) -> String.trim(value) != ""
      _other -> false
    end
  end

  defp provider_opts(%Client{} = client, %Request{} = request) do
    with :ok <- validate_response_format(request),
         :ok <- validate_option_set(client.defaults, :client_defaults),
         :ok <- validate_option_set(request.options, :request_options),
         :ok <- validate_option_model(client.model, client.defaults, request.options),
         {:ok, max_output_tokens} <- resolve_max_output_tokens(client.defaults, request),
         {:ok, receive_timeout} <- resolve_receive_timeout(client.defaults, request.options) do
      opts =
        client.defaults
        |> Keyword.merge(request.options)
        |> Keyword.drop([:model, :max_tokens, :max_output_tokens, :receive_timeout])
        |> maybe_put(:temperature, request.temperature)
        |> maybe_put(:top_p, request.top_p)
        |> maybe_put(:max_output_tokens, max_output_tokens)
        |> Keyword.put(:model, client.model)
        |> Keyword.put(:max_retries, 0)
        |> Keyword.put(
          :governed_authority,
          Keyword.fetch!(client.adapter_opts, :governed_authority)
        )

      {:ok, opts, receive_timeout}
    end
  end

  defp validate_response_format(%Request{response_format: nil}), do: :ok

  defp validate_response_format(%Request{}) do
    {:error,
     Error.unsupported_capability(:response_format,
       adapter: __MODULE__,
       message: "managed Gemini does not accept provider-neutral response_format"
     )}
  end

  defp validate_option_set(options, source) when is_list(options) do
    if Keyword.keyword?(options) do
      case Keyword.keys(options) -- @allowed_generation_options do
        [] ->
          validate_alias_values(options, source)

        fields ->
          {:error,
           Error.invalid(
             :managed_gemini_options,
             "managed Gemini rejects unmanaged or unsupported options",
             source: source,
             fields: Enum.uniq(fields)
           )}
      end
    else
      {:error,
       Error.invalid(
         :managed_gemini_options,
         "managed Gemini options must be a keyword list",
         source: source
       )}
    end
  end

  defp validate_alias_values(options, source) do
    case {Keyword.get(options, :max_tokens), Keyword.get(options, :max_output_tokens)} do
      {left, right} when not is_nil(left) and not is_nil(right) and left != right ->
        {:error,
         Error.invalid(
           :managed_gemini_option_mismatch,
           "managed Gemini max token options disagree",
           source: source
         )}

      _other ->
        :ok
    end
  end

  defp validate_option_model(model, defaults, request_options) do
    values =
      [Keyword.get(defaults, :model), Keyword.get(request_options, :model)]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&normalize_model/1)

    if Enum.all?(values, &(&1 == normalize_model(model))) do
      :ok
    else
      {:error,
       Error.invalid(
         :managed_gemini_model_mismatch,
         "managed Gemini model options do not match the client model"
       )}
    end
  end

  defp resolve_max_output_tokens(defaults, %Request{} = request) do
    request_option = Keyword.get(request.options, :max_tokens)
    provider_request_option = Keyword.get(request.options, :max_output_tokens)
    default = Keyword.get(defaults, :max_tokens) || Keyword.get(defaults, :max_output_tokens)
    value = request.max_tokens || request_option || provider_request_option || default

    if is_nil(value) or (is_integer(value) and value > 0) do
      {:ok, value}
    else
      {:error,
       Error.invalid(
         :managed_gemini_max_tokens,
         "managed Gemini max token limit must be a positive integer"
       )}
    end
  end

  defp resolve_receive_timeout(defaults, request_options) do
    value =
      Keyword.get(request_options, :receive_timeout) ||
        Keyword.get(defaults, :receive_timeout, @default_receive_timeout)

    if is_integer(value) and value > 0 do
      {:ok, value}
    else
      {:error,
       Error.invalid(
         :managed_gemini_receive_timeout,
         "managed Gemini receive timeout must be a positive integer"
       )}
    end
  end

  defp normalize_model("models/" <> model), do: model
  defp normalize_model(model) when is_binary(model), do: model
  defp normalize_model(model), do: model

  defp ensure_stream_provider do
    with :ok <- ensure_provider_function(:start_stream, 2),
         :ok <- ensure_provider_function(:subscribe_stream, 1),
         :ok <- ensure_provider_function(:stop_stream, 1) do
      :ok
    end
  end

  defp ensure_provider_function(function, arity),
    do: ensure_provider_function(Gemini, function, arity)

  defp ensure_provider_function(module, function, arity) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:error, Error.missing_dependency(module)}

      not function_exported?(module, function, arity) ->
        {:error, Error.missing_dependency(module, function: function, arity: arity)}

      true ->
        :ok
    end
  end

  defp provider_call(function, args), do: apply(Gemini, function, args)

  defp normalize_response(result, %Client{} = client, %Request{} = request, refs) do
    case extract_text(result) do
      text when is_binary(text) and text != "" ->
        {:ok,
         Response.new(
           id: response_field(result, [:response_id, :responseId, :id]),
           provider: :gemini,
           model: client.model,
           text: text,
           usage: extract_usage(result),
           finish_reason: extract_finish_reason(result),
           raw: result,
           metadata: Map.merge(client.metadata, %{managed_authority_refs: refs}),
           trace: %{adapter: __MODULE__, provider: :gemini, model: request.model || client.model}
         )}

      _empty ->
        {:error,
         Error.new(
           :invalid_response,
           :empty_provider_response,
           "managed Gemini returned no text"
         )}
    end
  end

  defp extract_text(text) when is_binary(text), do: text

  defp extract_text(result) when is_map(result) do
    direct = map_value(result, :text)

    if is_binary(direct) do
      direct
    else
      result
      |> map_value(:candidates, [])
      |> List.wrap()
      |> Enum.flat_map(&candidate_text_parts/1)
      |> Enum.join("")
    end
  end

  defp extract_text(_result), do: ""

  defp candidate_text_parts(candidate) when is_map(candidate) do
    candidate
    |> map_value(:content, %{})
    |> map_value(:parts, [])
    |> List.wrap()
    |> Enum.flat_map(fn part ->
      case map_value(part, :text) do
        text when is_binary(text) -> [text]
        _other -> []
      end
    end)
  end

  defp candidate_text_parts(_candidate), do: []

  defp extract_usage(result) when is_map(result) do
    result
    |> map_value(:usageMetadata, map_value(result, :usage_metadata))
    |> normalize_usage()
  end

  defp extract_usage(_result), do: nil

  defp normalize_usage(nil), do: nil

  defp normalize_usage(usage) when is_map(usage) do
    %{
      input_tokens: map_value(usage, :promptTokenCount, map_value(usage, :prompt_token_count)),
      output_tokens:
        map_value(usage, :candidatesTokenCount, map_value(usage, :candidates_token_count)),
      total_tokens: map_value(usage, :totalTokenCount, map_value(usage, :total_token_count)),
      cached_tokens:
        map_value(usage, :cachedContentTokenCount, map_value(usage, :cached_content_token_count)),
      thoughts_tokens:
        map_value(usage, :thoughtsTokenCount, map_value(usage, :thoughts_token_count))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_usage(_usage), do: nil

  defp extract_finish_reason(result) when is_map(result) do
    result
    |> map_value(:candidates, [])
    |> List.wrap()
    |> Enum.find_value(&map_value(&1, :finishReason, map_value(&1, :finish_reason)))
  end

  defp extract_finish_reason(_result), do: nil

  defp response_field(result, fields) do
    Enum.find_value(fields, &map_value(result, &1))
  end

  defp managed_stream(prompt, provider_opts, receive_timeout, refs) do
    Stream.resource(
      fn ->
        %{
          status: :starting,
          prompt: prompt,
          provider_opts: provider_opts,
          receive_timeout: receive_timeout,
          refs: refs,
          stream_id: nil,
          finish_reason: nil,
          usage: nil,
          provider_error_seen?: false
        }
      end,
      &stream_next/1,
      &close_stream/1
    )
  end

  defp stream_next(%{status: :done} = state), do: {:halt, state}

  defp stream_next(%{status: :starting} = state) do
    case provider_call(:start_stream, [state.prompt, state.provider_opts]) do
      {:ok, stream_id} when is_binary(stream_id) and stream_id != "" ->
        case provider_call(:subscribe_stream, [stream_id]) do
          :ok ->
            stream_next(%{state | status: :active, stream_id: stream_id})

          {:error, reason} ->
            _ = provider_call(:stop_stream, [stream_id])
            {[error_event(reason, state.refs)], %{state | status: :done, stream_id: stream_id}}
        end

      {:error, reason} ->
        {[error_event(reason, state.refs)], %{state | status: :done}}

      other ->
        {[error_event({:invalid_stream_start, safe_kind(other)}, state.refs)],
         %{state | status: :done}}
    end
  end

  defp stream_next(%{status: :active} = state) do
    receive do
      {:stream_event, stream_id, %{type: :data, data: data}} when stream_id == state.stream_id ->
        {events, state} = data_events(data, state)

        if events == [] do
          stream_next(state)
        else
          {events, state}
        end

      {:stream_event, stream_id, %{type: :error, error: reason}}
      when stream_id == state.stream_id ->
        {[error_event(reason, state.refs)], %{state | provider_error_seen?: true}}

      {:stream_event, stream_id, %{type: :complete}} when stream_id == state.stream_id ->
        stream_next(state)

      {:stream_complete, stream_id} when stream_id == state.stream_id ->
        if state.provider_error_seen? do
          {:halt, %{state | status: :done}}
        else
          {[done_event(state)], %{state | status: :done}}
        end

      {:stream_error, stream_id, reason} when stream_id == state.stream_id ->
        if state.provider_error_seen? do
          {:halt, %{state | status: :done}}
        else
          {[error_event(reason, state.refs)], %{state | status: :done}}
        end

      {:stream_cancelled, stream_id} when stream_id == state.stream_id ->
        {[
           %StreamEvent{
             type: :cancelled,
             data: nil,
             metadata: %{provider: :gemini, managed_authority_refs: state.refs}
           }
         ], %{state | status: :done}}

      _unrelated ->
        stream_next(state)
    after
      state.receive_timeout ->
        _ = provider_call(:stop_stream, [state.stream_id])

        error = Error.new(:timeout, :stream_timeout, "managed Gemini stream timed out")

        {[%StreamEvent{type: :error, data: error, metadata: stream_metadata(state.refs)}],
         %{state | status: :done}}
    end
  end

  defp data_events(data, state) do
    text = extract_text(data)
    usage = extract_stream_usage(data)
    finish_reason = extract_finish_reason(data)

    events =
      []
      |> maybe_append_event(text_event(text, state.refs))
      |> maybe_append_event(usage_event(usage, state.refs))

    events =
      if events == [] and is_nil(finish_reason) do
        [
          %StreamEvent{
            type: :message,
            data: data,
            metadata: stream_metadata(state.refs)
          }
        ]
      else
        events
      end

    {events,
     %{
       state
       | finish_reason: finish_reason || state.finish_reason,
         usage: usage || state.usage
     }}
  end

  defp extract_stream_usage(data) when is_map(data) do
    data
    |> map_value(:usageMetadata, map_value(data, :usage_metadata))
    |> normalize_stream_usage()
  end

  defp extract_stream_usage(_data), do: nil

  defp normalize_stream_usage(nil), do: nil

  defp normalize_stream_usage(usage) when is_map(usage) do
    %{
      input_tokens: map_value(usage, :promptTokenCount, map_value(usage, :prompt_token_count)),
      output_tokens:
        map_value(usage, :candidatesTokenCount, map_value(usage, :candidates_token_count)),
      total_tokens: map_value(usage, :totalTokenCount, map_value(usage, :total_token_count)),
      cached_tokens:
        map_value(usage, :cachedContentTokenCount, map_value(usage, :cached_content_token_count)),
      thoughts_tokens:
        map_value(usage, :thoughtsTokenCount, map_value(usage, :thoughts_token_count))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_stream_usage(_usage), do: nil

  defp text_event("", _refs), do: nil
  defp text_event(nil, _refs), do: nil

  defp text_event(text, refs) when is_binary(text) do
    %StreamEvent{type: :delta, data: text, metadata: stream_metadata(refs)}
  end

  defp usage_event(nil, _refs), do: nil

  defp usage_event(usage, refs) do
    %StreamEvent{type: :usage, data: usage, metadata: stream_metadata(refs)}
  end

  defp done_event(state) do
    %StreamEvent{
      type: :done,
      data: %{finish_reason: state.finish_reason, usage: state.usage},
      metadata: stream_metadata(state.refs)
    }
  end

  defp error_event(%Error{} = error, refs) do
    %StreamEvent{type: :error, data: error, metadata: stream_metadata(refs)}
  end

  defp error_event(reason, refs) do
    %StreamEvent{type: :error, data: provider_error(reason), metadata: stream_metadata(refs)}
  end

  defp stream_metadata(refs),
    do: %{provider: :gemini, provider_event_boundary: true, managed_authority_refs: refs}

  defp maybe_append_event(events, nil), do: events
  defp maybe_append_event(events, event), do: events ++ [event]

  defp close_stream(%{status: :active, stream_id: stream_id}) when is_binary(stream_id) do
    _ = provider_call(:stop_stream, [stream_id])
    :ok
  end

  defp close_stream(_state), do: :ok

  defp provider_error(reason) do
    Error.provider_error(safe_reason(reason), adapter: __MODULE__)
  end

  defp safe_reason(%Error{reason: reason}), do: reason
  defp safe_reason(reason) when is_atom(reason), do: reason
  defp safe_reason({reason, _details}) when is_atom(reason), do: reason
  defp safe_reason(_reason), do: :gemini_provider_error

  defp safe_kind(%{__struct__: module}) when is_atom(module), do: module
  defp safe_kind(value) when is_atom(value), do: value
  defp safe_kind(_value), do: :redacted

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp map_value(_map, _key, default), do: default

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
