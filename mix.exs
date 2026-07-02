defmodule Hedera.MixProject do
  use Mix.Project

  @version "0.5.0"
  @source_url "https://github.com/Alex-erl/hedera_ex"

  def project do
    [
      app: :hedera_ex,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Hedera",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto, :public_key, :inets, :ssl]]
  end

  defp deps do
    [
      {:mint, "~> 1.6"},
      {:jason, "~> 1.4"},
      {:protobuf, "~> 0.14"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "A native Elixir SDK for the Hedera network: keys (Ed25519 / ECDSA secp256k1), " <>
      "identifiers, protobuf encoding, gRPC, and Consensus + Crypto Service support."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["asv"],
      files: ~w(lib priv mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md", "CHANGELOG.md", "LICENSE"]]
  end
end
