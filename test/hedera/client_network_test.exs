defmodule Hedera.ClientNetworkTest do
  @moduledoc """
  Live testnet integration (excluded by default). Builds, signs and submits a
  real consensus message over gRPC; a pre-check code of 0 means the node
  accepted it (signature valid, body well-formed, fee sufficient) — which
  validates the protobuf field numbers and signing end-to-end.
  """
  use ExUnit.Case, async: false

  alias Hedera.{AccountId, Client, PrivateKey, Receipt, TokenId, TopicId}

  @moduletag :network
  @topic "0.0.9339331"

  defp operator do
    operator_id = AccountId.parse(System.fetch_env!("OPERATOR_ID"))
    operator_key = PrivateKey.from_string_ecdsa(System.fetch_env!("OPERATOR_KEY"))
    {operator_id, operator_key, Client.testnet(operator_id, operator_key)}
  end

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

  test "HTS: creates a fungible token then mints supply (receipt carries token id + supply)" do
    {operator_id, operator_key, client} = operator()
    pub = PrivateKey.public_key(operator_key)

    assert {:ok, create} =
             Client.create_token(client,
               name: "TrustLayer Test Token",
               symbol: "TLT",
               decimals: 0,
               initial_supply: 1000,
               treasury: operator_id,
               admin_key: pub,
               supply_key: pub
             )

    assert create.precheck_code == 0,
           "create pre-check #{create.precheck_code} (expected 0)"

    assert {:ok, r1} = Client.transaction_receipt(client, create.transaction_id)
    assert Receipt.success?(r1), "create receipt status #{r1.status}"
    assert %TokenId{} = token = r1.token_id

    # mint 500 more units; treasury (operator) holds them, supply key signs
    assert {:ok, mint} = Client.mint_token(client, token, 500)
    assert {:ok, r2} = Client.transaction_receipt(client, mint.transaction_id)
    assert Receipt.success?(r2), "mint receipt status #{r2.status}"
    assert r2.new_total_supply == 1500
  end

  test "HTS: associates the client account then transfers tokens to it (multi-sig)" do
    {operator_id, operator_key, client} = operator()
    pub = PrivateKey.public_key(operator_key)

    client_id = AccountId.parse(System.fetch_env!("CLIENT_ID"))
    # the client testnet account is an ED25519 account (see mirror node)
    client_key = PrivateKey.from_string_ed25519(System.fetch_env!("CLIENT_KEY"))

    # fresh token each run, so the client is never already associated
    assert {:ok, create} =
             Client.create_token(client,
               name: "TrustLayer Xfer",
               symbol: "TLX",
               decimals: 0,
               initial_supply: 100,
               treasury: operator_id,
               admin_key: pub,
               supply_key: pub
             )

    assert {:ok, r1} = Client.transaction_receipt(client, create.transaction_id)
    assert %TokenId{} = token = r1.token_id

    # associate: operator pays + signs, the client account also signs (multi-sig)
    assert {:ok, assoc} =
             Client.associate_token(client, client_id, [token], signers: [client_key])

    assert assoc.precheck_code == 0, "associate pre-check #{assoc.precheck_code}"
    assert {:ok, r2} = Client.transaction_receipt(client, assoc.transaction_id)
    assert Receipt.success?(r2), "associate receipt status #{r2.status}"

    # transfer 10 tokens operator -> client
    assert {:ok, xfer} =
             Client.transfer_token(client, token, [{operator_id, -10}, {client_id, 10}])

    assert {:ok, r3} = Client.transaction_receipt(client, xfer.transaction_id)
    assert Receipt.success?(r3), "transfer receipt status #{r3.status}"
  end
end
