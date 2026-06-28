defmodule Hedera.Network do
  @moduledoc "Known Hedera network nodes (cleartext gRPC endpoints)."

  alias Hedera.AccountId

  @type node_info :: %{account_id: AccountId.t(), host: binary(), port: :inet.port_number()}

  @doc "A default testnet consensus node (account 0.0.3)."
  @spec default_testnet_node() :: node_info()
  def default_testnet_node do
    %{account_id: AccountId.parse("0.0.3"), host: "0.testnet.hedera.com", port: 50_211}
  end

  @doc "A default mainnet consensus node (account 0.0.3)."
  @spec default_mainnet_node() :: node_info()
  def default_mainnet_node do
    %{account_id: AccountId.parse("0.0.3"), host: "35.237.200.180", port: 50_211}
  end
end
