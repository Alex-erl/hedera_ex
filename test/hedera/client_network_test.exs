defmodule Hedera.ClientNetworkTest do
  @moduledoc """
  Live testnet integration (excluded by default). Builds, signs and submits a
  real consensus message over gRPC; a pre-check code of 0 means the node
  accepted it (signature valid, body well-formed, fee sufficient) — which
  validates the protobuf field numbers and signing end-to-end.
  """
  use ExUnit.Case, async: false

  alias Hedera.{AccountId, Client, ContractId, FileId, MirrorNode, PrivateKey, Receipt, ScheduleId, TokenId, TopicId}

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

  defp await_success!(client, %{transaction_id: tx_id, precheck_code: pc}, label) do
    assert pc == 0, "#{label} pre-check #{pc} (expected 0)"
    assert {:ok, receipt} = Client.transaction_receipt(client, tx_id)
    assert Receipt.success?(receipt), "#{label} receipt status #{receipt.status} (expected 22)"
    receipt
  end

  test "HTS NFT: create non-fungible token, mint with metadata, pause/unpause" do
    {operator_id, operator_key, client} = operator()
    pub = PrivateKey.public_key(operator_key)

    assert {:ok, create} =
             Client.create_token(client,
               name: "TrustLayer NFT",
               symbol: "TLNFT",
               token_type: :nft,
               supply_type: :finite,
               max_supply: 100,
               treasury: operator_id,
               admin_key: pub,
               supply_key: pub,
               pause_key: pub
             )

    token = await_success!(client, create, "nft create").token_id
    assert token

    # mint two NFTs with metadata; receipt carries the assigned serial numbers
    assert {:ok, mint} = Client.mint_token(client, token, 0, metadata: ["ipfs://one", "ipfs://two"])
    r = await_success!(client, mint, "nft mint")
    assert r.serial_numbers == [1, 2], "expected serials [1,2], got #{inspect(r.serial_numbers)}"
    assert r.new_total_supply == 2

    # pause then unpause (pause key)
    assert {:ok, pause} = Client.pause_token(client, token)
    await_success!(client, pause, "pause")
    assert {:ok, unpause} = Client.unpause_token(client, token)
    await_success!(client, unpause, "unpause")
  end

  test "HTS management: kyc, NFT transfer, freeze/unfreeze, wipe with a second account" do
    {operator_id, operator_key, client} = operator()
    pub = PrivateKey.public_key(operator_key)

    client_id = AccountId.parse(System.fetch_env!("CLIENT_ID"))
    client_key = PrivateKey.from_string_ed25519(System.fetch_env!("CLIENT_KEY"))

    assert {:ok, create} =
             Client.create_token(client,
               name: "TrustLayer NFT Mgmt",
               symbol: "TLM",
               token_type: :nft,
               supply_type: :finite,
               max_supply: 100,
               treasury: operator_id,
               admin_key: pub,
               supply_key: pub,
               kyc_key: pub,
               freeze_key: pub,
               wipe_key: pub
             )

    token = await_success!(client, create, "create").token_id

    assert {:ok, mint} = Client.mint_token(client, token, 0, metadata: ["ipfs://x"])
    await_success!(client, mint, "mint")

    # the client must associate + be KYC-granted before it can receive
    assert {:ok, assoc} = Client.associate_token(client, client_id, [token], signers: [client_key])
    await_success!(client, assoc, "associate")

    assert {:ok, kyc} = Client.grant_kyc(client, token, client_id)
    await_success!(client, kyc, "grant_kyc")

    # transfer NFT serial 1 operator -> client
    assert {:ok, xfer} = Client.transfer_nft(client, token, [{operator_id, client_id, 1}])
    await_success!(client, xfer, "nft transfer")

    # freeze then unfreeze the client (freeze key)
    assert {:ok, fz} = Client.freeze_token(client, token, client_id)
    await_success!(client, fz, "freeze")
    assert {:ok, uf} = Client.unfreeze_token(client, token, client_id)
    await_success!(client, uf, "unfreeze")

    # wipe the NFT serial back off the client (wipe key)
    assert {:ok, wipe} = Client.wipe_token(client, token, client_id, serials: [1])
    await_success!(client, wipe, "wipe")
  end

  test "File Service: create -> append -> update -> delete" do
    {_operator_id, _operator_key, client} = operator()

    assert {:ok, create} = Client.create_file(client, contents: "trust-anchor-v1", file_memo: "tl")
    file = await_success!(client, create, "file create").file_id
    assert %FileId{} = file

    assert {:ok, append} = Client.append_file(client, file, " + more")
    await_success!(client, append, "file append")

    assert {:ok, update} = Client.update_file(client, file, contents: "trust-anchor-v2")
    await_success!(client, update, "file update")

    assert {:ok, delete} = Client.delete_file(client, file)
    await_success!(client, delete, "file delete")
  end

  test "Schedule Service: create a pending transfer, then sign it to execute" do
    {operator_id, _operator_key, client} = operator()
    client_id = AccountId.parse(System.fetch_env!("CLIENT_ID"))
    client_key = PrivateKey.from_string_ed25519(System.fetch_env!("CLIENT_KEY"))

    # scheduled transfer debits the client (1 tinybar) → needs the CLIENT's
    # signature, which the operator-created schedule does not yet have → pending
    # unique memo per run — Hedera dedupes identical schedules (status 210,
    # IDENTICAL_SCHEDULE_ALREADY_CREATED)
    assert {:ok, create} =
             Client.create_schedule(client,
               transfers: [{client_id, -1}, {operator_id, 1}],
               schedule_memo: "tl-scheduled-#{:os.system_time(:millisecond)}"
             )

    r = await_success!(client, create, "schedule create")
    assert %ScheduleId{} = schedule = r.schedule_id

    # the client adds its signature → the scheduled transfer executes
    assert {:ok, sign} = Client.sign_schedule(client, schedule, signers: [client_key])
    await_success!(client, sign, "schedule sign")
  end

  test "SmartContract Service: deploy inline bytecode then call the contract" do
    {_operator_id, _operator_key, client} = operator()

    # EVM init that deploys a 1-byte STOP (0x00) runtime: CODECOPY the last byte
    # to memory then RETURN it.
    bytecode = <<0x60, 0x01, 0x60, 0x0C, 0x60, 0x00, 0x39, 0x60, 0x01, 0x60, 0x00, 0xF3, 0x00>>

    assert {:ok, create} = Client.create_contract(client, bytecode: bytecode, gas: 200_000)
    r = await_success!(client, create, "contract create")
    assert %ContractId{} = contract = r.contract_id

    # call it: the STOP runtime halts cleanly (no return value)
    assert {:ok, call} = Client.call_contract(client, contract, gas: 100_000)
    await_success!(client, call, "contract call")

    # read the call's result from the record via the mirror node (return values
    # aren't in the receipt). Poll for mirror-node ingestion lag.
    result = poll_contract_result(call.transaction_id, 15)
    assert is_map(result), "no contract result from mirror node"
    assert Map.has_key?(result, "call_result")
    assert is_integer(result["gas_used"])
  end

  test "Allowances: operator approves the client, then the client spends operator HBAR via the allowance" do
    {operator_id, _operator_key, client} = operator()
    client_id = AccountId.parse(System.fetch_env!("CLIENT_ID"))
    client_key = PrivateKey.from_string_ed25519(System.fetch_env!("CLIENT_KEY"))
    spender = Client.testnet(client_id, client_key)

    # 1. operator (owner) approves the client to spend up to 10 tinybars
    assert {:ok, approve} =
             Client.approve_allowance(client, hbar_allowances: [{operator_id, client_id, 10}])

    await_success!(client, approve, "approve allowance")

    # 2. the client (spender), signing with its own key, moves 1 tinybar of the
    #    operator's HBAR to itself — authorized by the allowance (is_approval)
    assert {:ok, xfer} =
             Client.transfer_hbar(spender, [{operator_id, -1, true}, {client_id, 1}])

    assert xfer.precheck_code == 0, "approved transfer pre-check #{xfer.precheck_code}"
    await_success!(spender, xfer, "approved transfer")
  end

  defp poll_contract_result(_tx_id, 0), do: nil

  defp poll_contract_result(tx_id, attempts) do
    case MirrorNode.contract_result(tx_id) do
      {:ok, result} ->
        result

      {:error, _} ->
        Process.sleep(2_000)
        poll_contract_result(tx_id, attempts - 1)
    end
  end
end
