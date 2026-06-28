defmodule Hedera.Network do
  @moduledoc "Known Hedera network nodes (cleartext gRPC endpoints)."

  alias Hedera.AccountId

  @type node_info :: %{account_id: AccountId.t(), host: binary(), port: :inet.port_number()}

  @testnet [
    {"0.0.3", "0.testnet.hedera.com"},
    {"0.0.4", "1.testnet.hedera.com"},
    {"0.0.5", "2.testnet.hedera.com"},
    {"0.0.6", "3.testnet.hedera.com"}
  ]

  @doc "The testnet consensus-node address book (used for cross-node retry)."
  @spec testnet_nodes() :: [node_info()]
  def testnet_nodes do
    Enum.map(@testnet, fn {account, host} ->
      %{account_id: AccountId.parse(account), host: host, port: 50_211}
    end)
  end

  @doc "A single default testnet node (account 0.0.3)."
  @spec default_testnet_node() :: node_info()
  def default_testnet_node, do: hd(testnet_nodes())
end
