defmodule Inference.Message do
  @moduledoc """
  Provider-neutral chat message.
  """

  alias Inference.Error

  @roles [:system, :user, :assistant, :tool]

  @enforce_keys [:role, :content]
  defstruct [:role, :content, name: nil, metadata: %{}]

  @type role :: :system | :user | :assistant | :tool
  @type t :: %__MODULE__{
          role: role(),
          content: String.t(),
          name: String.t() | nil,
          metadata: map()
        }

  @spec roles() :: [role()]
  def roles, do: @roles

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = message), do: validate(message)
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    role = attrs[:role] || attrs["role"]
    content = attrs[:content] || attrs["content"]
    name = attrs[:name] || attrs["name"]
    metadata = attrs[:metadata] || attrs["metadata"] || %{}

    %__MODULE__{role: normalize_role(role), content: content, name: name, metadata: metadata}
    |> validate()
  end

  def new(other), do: {:error, Error.invalid(:message, "message must be a map", value: other)}

  defp validate(%__MODULE__{role: role}) when role not in @roles do
    {:error, Error.invalid(:role, "role must be one of #{inspect(@roles)}", role: role)}
  end

  defp validate(%__MODULE__{content: content}) when not is_binary(content) or content == "" do
    {:error, Error.invalid(:content, "content must be a non-empty string")}
  end

  defp validate(%__MODULE__{metadata: metadata}) when not is_map(metadata) do
    {:error, Error.invalid(:metadata, "metadata must be a map", metadata: metadata)}
  end

  defp validate(%__MODULE__{} = message), do: {:ok, message}

  defp normalize_role(role) when is_binary(role) do
    String.to_existing_atom(role)
  rescue
    ArgumentError -> role
  end

  defp normalize_role(role), do: role
end
