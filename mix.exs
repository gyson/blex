defmodule Blex.MixProject do
  use Mix.Project

  def project do
    [
      app: :blex,
      version: "0.2.0",
      description:
        "A fast Bloom filter with concurrent accessibility, powered by :atomics module",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      name: "Blex",
      source_url: "https://github.com/gyson/blex"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bloomex, "~> 1.0", only: :dev},
      {:benchee, "~> 0.13", only: :dev},
      {:murmur, "~> 1.0", only: [:dev, :test]},
      {:stream_data, "~> 0.4", only: [:dev, :test]},
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:ex_type, "~> 0.4.0", only: :dev, runtime: true},
      {:dialyxir, "~> 1.0.0-rc.4", only: :dev, runtime: false}
    ]
  end

  def package do
    %{
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/gyson/blex"}
    }
  end
end
