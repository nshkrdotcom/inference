defmodule Inference.DependencyBoundaryTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("../../../..", __DIR__)

  @forbidden_deps [
    :agent_session_manager,
    :gemini_ex,
    :req_llm,
    :req_llm_next,
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

    asm_examples =
      [
        Path.join(@repo_root, "examples/asm_adapter/text_only.exs"),
        Path.join(@repo_root, "examples/asm_adapter/tools_unsupported.exs"),
        Path.join(@repo_root, "examples/live_asm.exs")
      ]
      |> Enum.map_join("\n", &File.read!/1)

    assert docs =~ "Gemini API"
    assert docs =~ "Gemini CLI is retired"
    assert docs =~ "Antigravity"
    assert docs =~ "current Google coding-agent"
    assert asm_examples =~ ~s("antigravity" => :antigravity)
    assert asm_examples =~ ~s("cursor" => :cursor)
    refute asm_examples =~ ~s("gemini" => :gemini)
  end

  test "0.1.0 release metadata and root invocation are complete" do
    project = Mix.Project.config()
    package = project[:package]
    root_mix = File.read!(Path.join(@repo_root, "mix.exs"))
    changelog = File.read!(Path.join(@repo_root, "apps/inference/CHANGELOG.md"))
    license = File.read!(Path.join(@repo_root, "apps/inference/LICENSE"))

    assert project[:app] == :inference
    assert project[:version] == "0.1.0"
    assert project[:elixir] == "~> 1.18"
    assert package[:name] == :inference
    assert package[:licenses] == ["MIT"]
    assert project[:homepage_url] == "https://hex.pm/packages/inference"

    assert package[:links] == %{
             "Changelog" =>
               "https://github.com/nshkrdotcom/inference/blob/main/apps/inference/CHANGELOG.md",
             "GitHub" => "https://github.com/nshkrdotcom/inference",
             "Hex" => "https://hex.pm/packages/inference",
             "HexDocs" => "https://hexdocs.pm/inference",
             "License" =>
               "https://github.com/nshkrdotcom/inference/blob/main/apps/inference/LICENSE"
           }

    assert "lib" in package[:files]
    assert "LICENSE" in package[:files]
    assert project[:docs][:assets] == %{"assets" => "assets"}
    assert project[:docs][:homepage_url] == "https://hexdocs.pm/inference"
    assert changelog =~ "## 0.1.0 - 2026-07-13"
    assert license =~ "MIT License"
    assert root_mix =~ ~s({:ex_doc, "~> 0.38", only: [:dev, :test], runtime: false})
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
