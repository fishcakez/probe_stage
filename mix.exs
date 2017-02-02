defmodule ProbeStage.Mixfile do
  use Mix.Project

  def project do
    [app: :probe_stage,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [applications: [:gen_stage]]
  end

  defp deps do
    [gen_stage: "~> 0.10.0"]
  end
end
