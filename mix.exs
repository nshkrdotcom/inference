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
      deps: deps()
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end
end
