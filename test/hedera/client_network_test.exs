defmodule Hedera.ClientNetworkTest do
  @moduledoc """
  Live testnet integration (excluded by default). Builds, signs and submits a
  real consensus message over gRPC; a pre-check code of 0 means the node
  accepted it (signature valid, body well-formed, fee sufficient) — which
  validates the protobuf field numbers and signing end-to-end.
  """
  use ExUnit.Case, async: false

  alias Hedera.{AccountId, Client, PrivateKey, TopicId}

  @moduletag :network
  @topic "0.0.9339331"

  test "submits a message to a testnet HCS topic (precheck OK)" do
    operator_id = AccountId.parse(System.fetch_env!("OPERATOR_ID"))
    operator_key = PrivateKey.from_string_ecdsa(System.fetch_env!("OPERATOR_KEY"))
    client = Client.testnet(operator_id, operator_key)

    message = "hedera_ex native submit ##{:rand.uniform(1_000_000_000)}"

    assert {:ok, result} = Client.submit_message(client, TopicId.parse(@topic), message)

    assert result.precheck_code == 0,
           "node pre-check returned #{result.precheck_code} (expected 0 = OK)"

    assert result.ok?

    # fetch the consensus receipt (sequence number) via gRPC getTransactionReceipts
    assert {:ok, receipt} = Client.transaction_receipt(client, result.transaction_id)

    assert Hedera.Receipt.success?(receipt),
           "receipt status #{receipt.status} (expected 22 = SUCCESS)"

    assert is_integer(receipt.topic_sequence_number)
  end

  test "transfers 1 tinybar to the network fee account (precheck OK + SUCCESS receipt)" do
    operator_id = AccountId.parse(System.fetch_env!("OPERATOR_ID"))
    operator_key = PrivateKey.from_string_ecdsa(System.fetch_env!("OPERATOR_KEY"))
    client = Client.testnet(operator_id, operator_key)

    # 0.0.98 is the network fee-collection account — a valid recipient on every
    # network. Balanced transfer: -1 tinybar from operator, +1 to 0.0.98.
    fee_account = AccountId.parse("0.0.98")

    assert {:ok, result} =
             Client.transfer_hbar(client, [{operator_id, -1}, {fee_account, 1}])

    assert result.precheck_code == 0,
           "node pre-check returned #{result.precheck_code} (expected 0 = OK)"

    assert {:ok, receipt} = Client.transaction_receipt(client, result.transaction_id)

    assert Hedera.Receipt.success?(receipt),
           "receipt status #{receipt.status} (expected 22 = SUCCESS)"
  end
end
