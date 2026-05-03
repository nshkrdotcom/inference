defmodule Inference.SourcePolicyTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("../../..", __DIR__)

  @text_extensions [
    ".ex",
    ".exs",
    ".md",
    ".sh",
    ".py",
    ".js",
    ".ts",
    ".json",
    ".lock",
    ".svg"
  ]

  @text_basenames [
    ".formatter.exs",
    ".gitignore",
    ".tool-versions",
    "AGENTS.md",
    "CHECKLIST.md",
    "CHANGELOG.md",
    "LICENSE",
    "README.md",
    "mix.exs",
    "mix.lock"
  ]

  test "tracked source avoids unbounded atom creation" do
    assert_no_tracked_hits(atom_tokens())
  end

  test "tracked source avoids pattern engine APIs" do
    assert_no_tracked_hits(pattern_engine_tokens())
  end

  defp assert_no_tracked_hits(tokens) do
    hits =
      @repo_root
      |> tracked_text_files()
      |> Enum.flat_map(&file_hits(&1, tokens))

    assert hits == []
  end

  defp tracked_text_files(repo_root) do
    {output, 0} = System.cmd("git", ["-C", repo_root, "ls-files"])

    output
    |> String.split("\n", trim: true)
    |> Enum.filter(&text_file?/1)
  end

  defp text_file?(path) do
    Path.basename(path) in @text_basenames or Path.extname(path) in @text_extensions
  end

  defp file_hits(path, tokens) do
    content = File.read!(Path.join(@repo_root, path))

    tokens
    |> Enum.filter(&String.contains?(content, &1))
    |> Enum.map(fn token -> path <> " contains " <> inspect(token) end)
  end

  defp atom_tokens do
    [
      "String." <> "to_atom",
      "String." <> "to_existing_atom",
      "binary_" <> "to_atom",
      "binary_" <> "to_existing_atom",
      "list_" <> "to_atom",
      "list_" <> "to_existing_atom",
      <<?:, ?#, ?{>>,
      <<?:, ?", ?#, ?{>>
    ]
  end

  defp pattern_engine_tokens do
    [
      "reg" <> "ex",
      "Reg" <> "ex",
      "~" <> "r",
      ":re" <> ".",
      "String." <> "match",
      "Reg" <> "Exp",
      "reg" <> "exp",
      "re." <> "compile",
      "re." <> "search",
      "re." <> "match",
      "re." <> "fullmatch",
      "re." <> "sub",
      "re." <> "split",
      "re." <> "findall",
      "re." <> "finditer",
      "from " <> "re import",
      "import " <> "re"
    ]
  end
end
