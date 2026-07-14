defmodule Inference.DependencyBoundaryTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("../../../..", __DIR__)

  @forbidden_deps [
    :gemini_cli_sdk,
    :claude_agent_sdk,
    :codex_sdk,
    :amp_sdk
  ]

  test "inference does not declare provider SDK deps" do
    assert_forbidden_deps_absent(Mix.Project.config()[:deps], @forbidden_deps)
  end

  test "repo has dependency-source bootstrap without Weld adoption" do
    assert File.regular?(Path.join(@repo_root, "build_support/dependency_sources.exs"))
    assert File.regular?(Path.join(@repo_root, "build_support/dependency_sources.config.exs"))
    assert File.read!(Path.join(@repo_root, ".gitignore")) =~ ".dependency_sources.local.exs"

    root_mix = File.read!(Path.join(@repo_root, "mix.exs"))
    app_mix = File.read!(Path.join(@repo_root, "apps/inference/mix.exs"))

    assert root_mix =~ "build_support/dependency_sources.exs"
    refute String.contains?(root_mix <> app_mix, "{:weld")
  end

  test "docs distinguish Gemini API from retired Gemini CLI ownership" do
    docs =
      [
        Path.join(@repo_root, "apps/inference/README.md"),
        Path.join(@repo_root, "apps/inference/guides/architecture.md"),
        Path.join(@repo_root, "apps/inference/guides/clients_and_adapters.md"),
        Path.join(@repo_root, "apps/inference/guides/optional_providers.md")
      ]
      |> Enum.map_join("\n", &File.read!/1)

    assert docs =~ "Gemini API"
    assert docs =~ "Gemini CLI is retired"
    assert docs =~ "Antigravity"
    assert docs =~ "current Google coding-agent"
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
