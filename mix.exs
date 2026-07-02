defmodule Hedera.MixProject do
  use Mix.Project

  @version "0.8.0"
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
    "A native Elixir SDK for the Hedera network: Ed25519 / ECDSA secp256k1 keys, " <>
      "gRPC over HTTP/2, and the Consensus, Crypto (incl. accounts), Token (HTS), " <>
      "File, Schedule and Smart Contract services — plus EIP-1559 Ethereum transactions " <>
      "and free/paid queries."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["asv"],
      files: ~w(lib priv guides mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "guides/getting_started.md",
        "guides/transactions.md",
        "guides/queries.md",
        "guides/ethereum.md",
        "guides/cryptography.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: ~r{guides/.*}
      ],
      groups_for_modules: [
        "Client & transactions": [Hedera.Client, Hedera.Transaction, Hedera.Receipt],
        "Keys & cryptography": [
          Hedera.PrivateKey,
          Hedera.PublicKey,
          Hedera.Ethereum,
          Hedera.Rlp,
          Hedera.Crypto.Keccak,
          Hedera.Crypto.Secp256k1
        ],
        Identifiers: [
          Hedera.Id,
          Hedera.AccountId,
          Hedera.ContractId,
          Hedera.FileId,
          Hedera.ScheduleId,
          Hedera.TokenId,
          Hedera.TopicId,
          Hedera.TransactionId,
          Hedera.Timestamp,
          Hedera.Duration
        ],
        "Wire & network": [Hedera.Proto, Hedera.Grpc, Hedera.Network, Hedera.MirrorNode]
      ]
    ]
  end
end
