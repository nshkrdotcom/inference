defmodule Inference.Request do
  @moduledoc """
  Provider-neutral inference request.
  """

  alias Inference.{Error, Message}

  defstruct [
    :id,
    :messages,
    :model,
    :temperature,
    :top_p,
    :max_tokens,
    :response_format,
    :metadata,
    :trace_context,
    :session,
    stream?: false,
    options: []
  ]

  @type input :: String.t() | [Message.t() | map() | keyword()] | t()
  @type t :: %__MODULE__{
          id: String.t() | nil,
          messages: [Message.t()],
          model: String.t() | nil,
          temperature: number() | nil,
          top_p: number() | nil,
          max_tokens: pos_integer() | nil,
          response_format: term(),
          metadata: map(),
          trace_context: map() | nil,
          session: term(),
          stream?: boolean(),
          options: keyword()
        }

  @spec new(input(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, opts \\ [])

  def new(%__MODULE__{} = request, opts) do
    request
    |> merge_opts(opts)
    |> validate()
  end

  def new(prompt, opts) when is_binary(prompt) do
    from_prompt(prompt, opts)
  end

  def new(messages, opts) when is_list(messages) do
    from_messages(messages, opts)
  end

  def new(other, _opts),
    do: {:error, Error.invalid(:request, "unsupported request input", value: other)}

  @spec from_prompt(String.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def from_prompt(prompt, opts \\ []) when is_binary(prompt) do
    from_messages([%{role: :user, content: prompt}], opts)
  end

  @spec from_prompt!(String.t(), keyword()) :: t()
  def from_prompt!(prompt, opts \\ []) do
    case from_prompt(prompt, opts) do
      {:ok, request} -> request
      {:error, error} -> raise ArgumentError, Exception.message(error)
    end
  end

  @spec from_messages(list(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def from_messages(messages, opts \\ []) when is_list(messages) do
    with {:ok, normalized} <- normalize_messages(messages) do
      %__MODULE__{
        id: Keyword.get(opts, :id),
        messages: normalized,
        model: Keyword.get(opts, :model),
        temperature: Keyword.get(opts, :temperature),
        top_p: Keyword.get(opts, :top_p),
        max_tokens: Keyword.get(opts, :max_tokens),
        response_format: Keyword.get(opts, :response_format),
        metadata: Keyword.get(opts, :metadata, %{}),
        trace_context: Keyword.get(opts, :trace_context),
        session: Keyword.get(opts, :session),
        stream?: Keyword.get(opts, :stream?, false),
        options: Keyword.get(opts, :options, [])
      }
      |> validate()
    end
  end

  @spec from_messages!(list(), keyword()) :: t()
  def from_messages!(messages, opts \\ []) do
    case from_messages(messages, opts) do
      {:ok, request} -> request
      {:error, error} -> raise ArgumentError, Exception.message(error)
    end
  end

  @spec to_prompt(t()) :: String.t()
  def to_prompt(%__MODULE__{messages: messages}) do
    Enum.map_join(messages, "\n\n", fn %Message{role: role, content: content} ->
      "#{role}: #{content}"
    end)
  end

  @spec user_prompt(t()) :: String.t()
  def user_prompt(%__MODULE__{messages: messages}) do
    messages
    |> Enum.filter(&(&1.role == :user))
    |> Enum.map_join("\n\n", & &1.content)
  end

  defp normalize_messages(messages) do
    Enum.reduce_while(messages, {:ok, []}, fn message, {:ok, acc} ->
      case Message.new(message) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp merge_opts(%__MODULE__{} = request, []), do: request

  defp merge_opts(%__MODULE__{} = request, opts) do
    Enum.reduce(opts, request, fn {key, value}, acc ->
      if Map.has_key?(acc, key), do: Map.put(acc, key, value), else: acc
    end)
  end

  defp validate(%__MODULE__{messages: messages}) when not is_list(messages) or messages == [] do
    {:error, Error.invalid(:messages, "messages must be a non-empty list")}
  end

  defp validate(%__MODULE__{metadata: metadata}) when not is_map(metadata) do
    {:error, Error.invalid(:metadata, "metadata must be a map", metadata: metadata)}
  end

  defp validate(%__MODULE__{options: options}) when not is_list(options) do
    {:error, Error.invalid(:options, "options must be a keyword list", options: options)}
  end

  defp validate(%__MODULE__{} = request), do: {:ok, request}
end
