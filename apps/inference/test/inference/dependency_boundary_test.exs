defmodule Inference.DependencyBoundaryTest do
  use ExUnit.Case, async: true

  @forbidden_deps [
    :gemini_cli_sdk,
    :claude_agent_sdk,
    :codex_sdk,
    :amp_sdk
  ]

  test "inference does not declare provider SDK deps" do
    assert_forbidden_deps_absent(Mix.Project.config()[:deps], @forbidden_deps)
  end

  defp assert_forbidden_deps_absent(deps, forbidden_deps) when is_list(deps) do
    declared = MapSet.new(Enum.map(deps, &dep_name/1))

    Enum.each(forbidden_deps, fn dep ->
      refute MapSet.member?(declared, dep),
             "inference must not declare dependency on #{inspect(dep)}"
    end)
  end

  defp dep_name({name, _requirement}), do: name
  defp dep_name({name, _requirement, _opts}), do: name
end
