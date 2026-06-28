defmodule Hedera.NetworkTest do
  use ExUnit.Case, async: true

  alias Hedera.{AccountId, Network}

  test "testnet address book lists multiple consensus nodes" do
    nodes = Network.testnet_nodes()

    assert length(nodes) >= 2

    assert Enum.all?(nodes, fn n ->
             match?(%AccountId{}, n.account_id) and is_binary(n.host) and n.port == 50_211
           end)

    assert Network.default_testnet_node() == hd(nodes)
  end
end
