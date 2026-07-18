defmodule ZongziFeasibility.MixProject do
  use Mix.Project

  def project do
    [
      app: :zongzi_feasibility,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      # 契约
      {:zongzi, path: "../zongzi"},

      # 序列化与通信
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.4"},

      # Python 绑定
      {:pythonx, "~> 0.4.0"}
    ]
  end
end
