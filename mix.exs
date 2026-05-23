unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("build_support/dependency_sources.exs", __DIR__)
end

defmodule InferenceWorkspace.MixProject do
  use Mix.Project

  def project do
    [
      app: :inference_workspace,
      version: "0.1.0",
      apps_path: "apps",
      deps: deps(),
      aliases: aliases()
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      ci: [&run_inference_ci/1]
    ]
  end

  defp run_inference_ci(_args) do
    {_output, status} =
      System.cmd("mix", ["ci"],
        cd: "apps/inference",
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status == 0, do: :ok, else: Mix.raise("apps/inference mix ci failed")
  end
end
