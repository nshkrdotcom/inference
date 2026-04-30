defmodule Inference.Adapters.ASM do
  @moduledoc """
  Adapter for Agent Session Manager.

  The consuming application must install and configure `:agent_session_manager`.
  """

  @behaviour Inference.Adapter

  alias Inference.Adapters.Shared
  alias Inference.{Client, Error, Request, StreamEvent}

  @unadmitted_tool_keys [:tools, :tool_choice, :host_tools, :dynamic_tools, :allowed_tools]

  @impl true
  def complete(%Client{} = client, %Request{} = request) do
    module = Keyword.get(client.adapter_opts, :asm_module, ASM)

    with :ok <- Shared.ensure_dependency(module),
         {target, opts} <- query_target_and_opts(client, request),
         :ok <- validate_target(target),
         :ok <- validate_common_opts(client, module, opts),
         {:ok, result} <- call_query(module, target, prompt(request), opts) do
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
         {:ok, session, opts, ownership} <- stream_session(module, client, request),
         :ok <- validate_common_opts(client, module, opts),
         {:ok, raw_stream} <- call_stream(module, session, prompt(request), opts) do
      {:ok,
       raw_stream
       |> maybe_close_after_stream(module, session, ownership)
       |> Stream.flat_map(&stream_events/1)}
    else
      {:error, reason} -> {:error, Shared.normalize_error(reason, adapter: __MODULE__)}
    end
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

  defp query_target_and_opts(%Client{} = client, %Request{} = request) do
    opts = query_opts(client, request)

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

  defp stream_session(module, %Client{} = client, %Request{} = request) do
    opts = stream_opts(client, request)

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
    client
    |> common_opts(request)
    |> Keyword.merge(Keyword.get(client.adapter_opts, :query_opts, []))
  end

  defp stream_opts(%Client{} = client, %Request{} = request) do
    client
    |> common_opts(request)
    |> Keyword.merge(Keyword.get(client.adapter_opts, :stream_opts, []))
  end

  defp common_opts(%Client{} = client, %Request{} = request) do
    client
    |> Shared.request_opts(request)
    |> Keyword.drop([:temperature, :top_p, :max_tokens, :response_format, :prompt])
    |> rename_timeout()
  end

  defp validate_common_opts(%Client{} = client, module, opts) when is_list(opts) do
    case reject_unadmitted_tool_opts(opts) do
      :ok -> strict_asm_preflight(client, module, opts)
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp reject_unadmitted_tool_opts(opts) when is_list(opts) do
    case Enum.find(@unadmitted_tool_keys, &Keyword.has_key?(opts, &1)) do
      nil ->
        :ok

      key ->
        {:error,
         Error.unsupported_capability(:asm_tools,
           message:
             "ASM adapter does not support inference tools or provider-native tool controls yet; rejected #{inspect(key)}",
           key: key
         )}
    end
  end

  defp strict_asm_preflight(%Client{provider: provider} = client, module, opts)
       when is_atom(provider) and is_list(opts) do
    options_module =
      Keyword.get(client.adapter_opts, :asm_options_module, Module.concat([module, :Options]))

    with :ok <- Shared.ensure_dependency(options_module),
         true <- function_exported?(options_module, :preflight, 3) do
      options_module.preflight(provider, opts, mode: :strict_common)
      |> case do
        {:ok, _preflight} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      false ->
        {:error, Error.missing_dependency(options_module, function: :preflight)}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp strict_asm_preflight(%Client{} = _client, _module, _opts), do: :ok

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
