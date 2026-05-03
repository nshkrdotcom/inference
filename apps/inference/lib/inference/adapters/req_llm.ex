defmodule Inference.Adapters.ReqLLM do
  @moduledoc """
  Compatibility adapter for existing ReqLLM-style clients.
  """

  @behaviour Inference.Adapter

  alias Inference.Adapters.Shared
  alias Inference.{Client, Error, Request}

  @default_models %{
    openai: "gpt-5.4-mini",
    gemini: "gemini-3.1-flash-lite-preview",
    anthropic: "claude-haiku-4-5"
  }

  @env_vars %{
    gemini: ["GEMINI_API_KEY", "GOOGLE_API_KEY"],
    google: ["GOOGLE_API_KEY", "GEMINI_API_KEY"],
    openai: ["OPENAI_API_KEY"],
    anthropic: ["ANTHROPIC_API_KEY"]
  }

  @impl true
  def complete(%Client{} = client, %Request{} = request) do
    module = Keyword.get(client.adapter_opts, :req_llm_module, ReqLLM)

    with :ok <- Shared.ensure_dependency(module),
         model_spec when not is_nil(model_spec) <- model_spec(client, request),
         :ok <- maybe_put_provider_key(module, client, api_key(client, request)),
         opts <- request_opts(client, request),
         {:ok, result} <- call_generate(module, model_spec, request, opts) do
      object = unwrap_object(result, client, request)
      text = object_text(object) || Shared.extract_text(result)

      {:ok,
       Shared.response_from_result(result, client, request,
         text: text,
         metadata: %{model_spec: model_spec},
         object: object
       )}
    else
      nil -> {:error, Error.invalid(:model, "ReqLLM model is required")}
      {:error, reason} -> {:error, Shared.normalize_error(reason, adapter: __MODULE__)}
    end
  end

  @impl true
  def stream(%Client{} = _client, %Request{} = _request) do
    {:error, Error.unsupported_capability(:stream, adapter: __MODULE__)}
  end

  defp model_spec(%Client{} = client, %Request{} = request) do
    Keyword.get(client.adapter_opts, :model_spec) ||
      %{
        provider: client.provider,
        id: request.model || client.model || default_model(client.provider)
      }
  end

  defp request_opts(%Client{} = client, %Request{} = request) do
    client
    |> Shared.request_opts(request)
    |> Keyword.drop([:model, :prompt, :response_format, :schema])
    |> maybe_put(:api_key, api_key(client, request))
    |> maybe_convert_tools()
  end

  defp call_generate(module, model_spec, %Request{} = request, opts) do
    case schema(request) do
      nil -> call_generate_text(module, model_spec, prompt(request), opts)
      schema -> call_generate_object(module, model_spec, prompt(request), schema, opts)
    end
  end

  defp call_generate_text(module, model_spec, prompt, opts) do
    cond do
      function_exported?(module, :generate_text, 3) ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(module, :generate_text, [model_spec, prompt, opts])

      function_exported?(module, :generate, 3) ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(module, :generate, [model_spec, prompt, opts])

      true ->
        {:error, Error.missing_dependency(module, function: :generate_text)}
    end
  end

  defp call_generate_object(module, model_spec, prompt, schema, opts) do
    if function_exported?(module, :generate_object, 4) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(module, :generate_object, [model_spec, prompt, schema, opts])
    else
      {:error, Error.missing_dependency(module, function: :generate_object)}
    end
  end

  defp prompt(%Request{options: options} = request) do
    Keyword.get(options, :prompt) || Request.to_prompt(request)
  end

  defp schema(%Request{response_format: nil, options: options}), do: Keyword.get(options, :schema)
  defp schema(%Request{response_format: {:json_schema, schema}}), do: schema
  defp schema(%Request{response_format: response_format}), do: response_format

  defp unwrap_object(result, %Client{} = client, %Request{} = request) do
    if is_nil(schema(request)) do
      nil
    else
      unwrap_structured_object(result, client)
    end
  end

  defp unwrap_structured_object(result, %Client{} = client) do
    response_module = Keyword.get(client.adapter_opts, :response_module)

    if is_atom(response_module) and function_exported?(response_module, :unwrap_object, 1) do
      case response_module.unwrap_object(result) do
        {:ok, object} -> object
        _other -> Shared.extract_field(result, :object)
      end
    else
      Shared.extract_field(result, :object)
    end
  end

  defp object_text(%{"instruction" => instruction}) when is_binary(instruction), do: instruction
  defp object_text(%{instruction: instruction}) when is_binary(instruction), do: instruction
  defp object_text(_object), do: nil

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_convert_tools(opts) do
    case Keyword.get(opts, :tools) do
      tools when is_list(tools) -> Keyword.put(opts, :tools, Enum.map(tools, &to_req_llm_tool/1))
      _other -> opts
    end
  end

  defp to_req_llm_tool(%{__struct__: module} = tool) do
    req_tool_module = Module.concat([ReqLLM, Tool])

    with true <- portable_tool?(tool),
         true <- Code.ensure_loaded?(req_tool_module),
         true <- function_exported?(req_tool_module, :new, 1),
         {:ok, req_tool} <- req_tool_module.new(req_tool_opts(module, tool)) do
      req_tool
    else
      _other -> tool
    end
  end

  defp to_req_llm_tool(tool), do: tool

  defp portable_tool?(tool) do
    Enum.all?([:name, :description, :input_schema, :run], &Map.has_key?(tool, &1))
  end

  defp req_tool_opts(_module, tool) do
    callback =
      if is_function(tool.run, 2) do
        fn args -> tool.run.(args, %{}) end
      else
        tool.run
      end

    [
      name: tool.name,
      description: tool.description,
      parameter_schema: tool.input_schema,
      callback: callback
    ]
  end

  defp maybe_put_provider_key(_module, _client, nil), do: :ok

  defp maybe_put_provider_key(module, %Client{} = client, api_key) do
    provider_key = provider_key(client.provider)

    if function_exported?(module, :put_key, 2) and provider_key do
      module.put_key(provider_key, api_key)
    else
      :ok
    end
  end

  defp api_key(%Client{} = client, %Request{} = request) do
    Keyword.get(request.options, :api_key) ||
      Keyword.get(client.adapter_opts, :api_key) ||
      env_api_key(client)
  end

  defp env_api_key(%Client{} = client) do
    env = Keyword.get(client.adapter_opts, :env, &System.get_env/1)

    client.provider
    |> env_vars()
    |> Enum.find_value(fn key ->
      case env.(key) do
        value when is_binary(value) and value != "" -> value
        _other -> nil
      end
    end)
  end

  defp env_vars(provider), do: Map.get(@env_vars, provider, [])

  defp provider_key(:openai), do: :openai_api_key
  defp provider_key(:gemini), do: :google_api_key
  defp provider_key(:google), do: :google_api_key
  defp provider_key(:anthropic), do: :anthropic_api_key
  defp provider_key(_provider), do: nil

  defp default_model(provider), do: Map.get(@default_models, provider)
end
