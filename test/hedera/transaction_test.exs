defmodule Hedera.TransactionTest do
  use ExUnit.Case, async: true

  alias Hedera.{AccountId, ContractId, FileId, PrivateKey, PublicKey, Proto, ScheduleId, TokenId, TopicId, Transaction}

  defp decode_signed(tx) do
    # Transaction { signedTransactionBytes = 5 } -> SignedTransaction
    signed = Proto.field(Proto.decode(tx), 5)
    assert is_binary(signed)
    Proto.decode(signed)
  end

  test "submit_message: full nesting and the signature verifies over bodyBytes (ECDSA)" do
    key = PrivateKey.generate_ecdsa()

    %{transaction: tx, transaction_id: _} =
      Transaction.submit_message(
        operator_id: AccountId.parse("0.0.8260469"),
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        topic_id: TopicId.parse("0.0.9339331"),
        message: "hello"
      )

    sd = decode_signed(tx)
    body = Proto.field(sd, 1)
    sig_map = Proto.field(sd, 2)

    # SignatureMap{sigPair=1} -> SignaturePair{pubKeyPrefix=1, ECDSASecp256k1=6}
    pair = Proto.decode(Proto.field(Proto.decode(sig_map), 1))
    prefix = Proto.field(pair, 1)
    sig = Proto.field(pair, 6)

    assert prefix == PublicKey.to_bytes(PrivateKey.public_key(key))
    assert byte_size(sig) == 64
    # the recorded signature verifies over the EXACT transmitted body
    assert PublicKey.verify(PrivateKey.public_key(key), body, sig)

    # TransactionBody fields
    b = Proto.decode(body)
    assert is_binary(Proto.field(b, 1))
    assert is_binary(Proto.field(b, 2))
    assert is_integer(Proto.field(b, 3))
    submit = Proto.decode(Proto.field(b, 27))
    assert Proto.field(submit, 2) == "hello"
  end

  test "submit_message: ed25519 uses signature field 3 with a 32-byte key prefix" do
    key = PrivateKey.generate_ed25519()

    %{transaction: tx} =
      Transaction.submit_message(
        operator_id: AccountId.parse("0.0.2"),
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        topic_id: TopicId.parse("0.0.1"),
        message: "x"
      )

    sd = decode_signed(tx)
    pair = Proto.decode(Proto.field(Proto.decode(Proto.field(sd, 2)), 1))

    assert byte_size(Proto.field(pair, 1)) == 32
    sig = Proto.field(pair, 3)
    assert PublicKey.verify(PrivateKey.public_key(key), Proto.field(sd, 1), sig)
  end

  test "crypto_transfer encodes a balanced cryptoTransfer body (field 14) with sint64 amounts" do
    key = PrivateKey.generate_ecdsa()
    from = AccountId.parse("0.0.8260469")
    to = AccountId.parse("0.0.98")

    %{transaction: tx} =
      Transaction.crypto_transfer(
        operator_id: from,
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        transfers: [{from, -1}, {to, 1}]
      )

    sd = decode_signed(tx)
    body = Proto.field(sd, 1)

    # signature still verifies over the exact transmitted body
    sig = Proto.field(Proto.decode(Proto.field(Proto.decode(Proto.field(sd, 2)), 1)), 6)
    assert PublicKey.verify(PrivateKey.public_key(key), body, sig)

    # CryptoTransferTransactionBody { transfers = 1 } -> TransferList { accountAmounts = 1 }
    crypto_body = Proto.decode(Proto.field(Proto.decode(body), 14))
    transfer_list = Proto.decode(Proto.field(crypto_body, 1))

    # collect every repeated AccountAmount (field 1)
    account_amounts =
      for {1, _wire, v} <- transfer_list, do: Proto.decode(v)

    assert length(account_amounts) == 2
    raw_amounts = Enum.map(account_amounts, fn aa -> Proto.field(aa, 2) end)
    # sint64 ZigZag: -1 -> 1, +1 -> 2
    assert raw_amounts == [1, 2]
  end

  test "token_create encodes a tokenCreation body (field 29) with name/symbol/treasury and Keys" do
    key = PrivateKey.generate_ecdsa()
    pub = PrivateKey.public_key(key)
    treasury = AccountId.parse("0.0.8260469")

    %{transaction: tx} =
      Transaction.token_create(
        operator_id: treasury,
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        name: "TrustLayer Token",
        symbol: "TLT",
        decimals: 2,
        initial_supply: 1000,
        treasury: treasury,
        admin_key: pub,
        supply_key: pub
      )

    sd = decode_signed(tx)
    body = Proto.decode(Proto.field(sd, 1))
    tc = Proto.decode(Proto.field(body, 29))

    assert Proto.field(tc, 1) == "TrustLayer Token"
    assert Proto.field(tc, 2) == "TLT"
    assert Proto.field(tc, 3) == 2
    assert Proto.field(tc, 4) == 1000
    # treasury (5) is an AccountID sub-message
    assert is_binary(Proto.field(tc, 5))
    # adminKey (6) and supplyKey (10) are Key messages: ECDSA secp256k1 in field 7
    admin_key = Proto.decode(Proto.field(tc, 6))
    assert Proto.field(admin_key, 7) == PublicKey.to_bytes(pub)
    supply_key = Proto.decode(Proto.field(tc, 10))
    assert Proto.field(supply_key, 7) == PublicKey.to_bytes(pub)
  end

  test "ed25519 admin key encodes in Key field 2" do
    key = PrivateKey.generate_ed25519()
    pub = PrivateKey.public_key(key)

    %{transaction: tx} =
      Transaction.token_create(
        operator_id: AccountId.parse("0.0.2"),
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        treasury: AccountId.parse("0.0.2"),
        admin_key: pub
      )

    body = Proto.decode(Proto.field(decode_signed(tx), 1))
    admin_key = Proto.decode(Proto.field(Proto.decode(Proto.field(body, 29)), 6))
    assert Proto.field(admin_key, 2) == PublicKey.to_bytes(pub)
  end

  test "token_mint encodes a tokenMint body (field 37) with token and amount" do
    key = PrivateKey.generate_ecdsa()

    %{transaction: tx} =
      Transaction.token_mint(
        operator_id: AccountId.parse("0.0.2"),
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        token: TokenId.parse("0.0.777"),
        amount: 500
      )

    body = Proto.decode(Proto.field(decode_signed(tx), 1))
    mint = Proto.decode(Proto.field(body, 37))
    assert is_binary(Proto.field(mint, 1))
    assert Proto.field(mint, 2) == 500
  end

  test "token_associate is a field-40 body and supports multi-sig (operator + account key)" do
    operator_key = PrivateKey.generate_ecdsa()
    account_key = PrivateKey.generate_ed25519()
    account = AccountId.parse("0.0.8983395")

    %{transaction: tx} =
      Transaction.token_associate(
        operator_id: AccountId.parse("0.0.8260469"),
        operator_key: operator_key,
        node_account_id: AccountId.parse("0.0.3"),
        account: account,
        tokens: [TokenId.parse("0.0.777")],
        signers: [account_key]
      )

    sd = decode_signed(tx)
    body = Proto.field(sd, 1)
    assert is_binary(Proto.field(Proto.decode(body), 40))

    # SignatureMap has two distinct sigPairs, both valid over the body
    pairs = for {1, _w, v} <- Proto.decode(Proto.field(sd, 2)), do: Proto.decode(v)
    assert length(pairs) == 2

    # operator signed with ECDSA (field 6); account signed with ed25519 (field 3)
    assert PublicKey.verify(PrivateKey.public_key(operator_key), body, Proto.field(hd(pairs), 6))
    ed_pair = Enum.find(pairs, fn p -> Proto.field(p, 3) != nil end)
    assert PublicKey.verify(PrivateKey.public_key(account_key), body, Proto.field(ed_pair, 3))
  end

  test "crypto_transfer carries token transfers (CryptoTransferTransactionBody field 2)" do
    key = PrivateKey.generate_ecdsa()
    from = AccountId.parse("0.0.8260469")
    to = AccountId.parse("0.0.8983395")
    token = TokenId.parse("0.0.777")

    %{transaction: tx} =
      Transaction.crypto_transfer(
        operator_id: from,
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        token_transfers: [{token, [{from, -5}, {to, 5}]}]
      )

    crypto_body = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 14))
    # no HBAR TransferList (field 1) when only tokens move
    assert Proto.field(crypto_body, 1) == nil

    # TokenTransferList { token = 1, repeated AccountAmount transfers = 2 }
    ttl = Proto.decode(Proto.field(crypto_body, 2))
    assert is_binary(Proto.field(ttl, 1))
    aas = for {2, _w, v} <- ttl, do: Proto.field(Proto.decode(v), 2)
    # sint64 ZigZag: -5 -> 9, +5 -> 10
    assert aas == [9, 10]
  end

  test "token_create sets kyc/freeze/wipe/pause keys (fields 7/8/9/22)" do
    key = PrivateKey.generate_ecdsa()
    pub = PrivateKey.public_key(key)
    treasury = AccountId.parse("0.0.8260469")

    %{transaction: tx} =
      Transaction.token_create(
        operator_id: treasury,
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        treasury: treasury,
        token_type: :nft,
        supply_type: :finite,
        max_supply: 100,
        supply_key: pub,
        kyc_key: pub,
        freeze_key: pub,
        wipe_key: pub,
        pause_key: pub
      )

    tc = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 29))
    # NON_FUNGIBLE_UNIQUE = 1, FINITE = 1
    assert Proto.field(tc, 17) == 1
    assert Proto.field(tc, 18) == 1
    assert Proto.field(tc, 19) == 100

    for field <- [7, 8, 9, 10, 22] do
      key_msg = Proto.decode(Proto.field(tc, field))
      assert Proto.field(key_msg, 7) == PublicKey.to_bytes(pub)
    end
  end

  test "token_mint with NFT metadata encodes repeated field 3" do
    key = PrivateKey.generate_ecdsa()

    %{transaction: tx} =
      Transaction.token_mint(
        operator_id: AccountId.parse("0.0.2"),
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        token: TokenId.parse("0.0.777"),
        metadata: ["ipfs://a", "ipfs://b"]
      )

    mint = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 37))
    metas = for {3, _w, v} <- mint, do: v
    assert metas == ["ipfs://a", "ipfs://b"]
  end

  test "token management bodies carry the right field numbers" do
    key = PrivateKey.generate_ecdsa()
    base = [operator_id: AccountId.parse("0.0.2"), operator_key: key, node_account_id: AccountId.parse("0.0.3")]
    token = TokenId.parse("0.0.777")
    account = AccountId.parse("0.0.8983395")

    for {fun, field} <- [
          {:token_freeze, 31},
          {:token_unfreeze, 32},
          {:token_grant_kyc, 33},
          {:token_revoke_kyc, 34}
        ] do
      %{transaction: tx} = apply(Transaction, fun, [base ++ [token: token, account: account]])
      body = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), field))
      assert is_binary(Proto.field(body, 1))
      assert is_binary(Proto.field(body, 2))
    end

    # pause/unpause: { token = 1 } only
    %{transaction: tx} = Transaction.token_pause(base ++ [token: token])
    assert is_binary(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 46))

    %{transaction: tx} = Transaction.token_unpause(base ++ [token: token])
    assert is_binary(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 47))
  end

  test "token_wipe carries account + NFT serials (field 39)" do
    key = PrivateKey.generate_ecdsa()

    %{transaction: tx} =
      Transaction.token_wipe(
        operator_id: AccountId.parse("0.0.2"),
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        token: TokenId.parse("0.0.777"),
        account: AccountId.parse("0.0.8983395"),
        serials: [1, 2, 3]
      )

    wipe = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 39))
    # repeated int64 serialNumbers is packed (proto3 canonical): one field-4
    # length-delimited entry holding concatenated varints.
    assert Proto.decode_varints(Proto.field(wipe, 4)) == [1, 2, 3]
  end

  test "crypto_transfer carries NFT transfers (TokenTransferList.nftTransfers = 3)" do
    key = PrivateKey.generate_ecdsa()
    sender = AccountId.parse("0.0.8260469")
    receiver = AccountId.parse("0.0.8983395")
    token = TokenId.parse("0.0.777")

    %{transaction: tx} =
      Transaction.crypto_transfer(
        operator_id: sender,
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        nft_transfers: [{token, [{sender, receiver, 7}]}]
      )

    crypto_body = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 14))
    ttl = Proto.decode(Proto.field(crypto_body, 2))
    nft = Proto.decode(Proto.field(ttl, 3))
    assert is_binary(Proto.field(nft, 1))
    assert is_binary(Proto.field(nft, 2))
    assert Proto.field(nft, 3) == 7
  end

  test "file_create encodes fileCreate (17): expiry(2), KeyList(3), contents(4)" do
    key = PrivateKey.generate_ecdsa()
    pub = PrivateKey.public_key(key)

    %{transaction: tx} =
      Transaction.file_create(
        operator_id: AccountId.parse("0.0.2"),
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        contents: "trust-anchor-bytes",
        file_memo: "tl"
      )

    fc = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 17))
    assert is_binary(Proto.field(fc, 2))
    # KeyList { keys = 1 } → default is the operator's key (ECDSA in Key field 7)
    key_in_list = Proto.decode(Proto.field(Proto.decode(Proto.field(fc, 3)), 1))
    assert Proto.field(key_in_list, 7) == PublicKey.to_bytes(pub)
    assert Proto.field(fc, 4) == "trust-anchor-bytes"
    assert Proto.field(fc, 8) == "tl"
  end

  test "file append/update/delete carry fileID at the right field numbers" do
    key = PrivateKey.generate_ecdsa()
    base = [operator_id: AccountId.parse("0.0.2"), operator_key: key, node_account_id: AccountId.parse("0.0.3")]
    file = FileId.parse("0.0.111")

    %{transaction: tx} = Transaction.file_append(base ++ [file: file, contents: "more"])
    fa = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 16))
    assert is_binary(Proto.field(fa, 2))
    assert Proto.field(fa, 4) == "more"

    %{transaction: tx} = Transaction.file_update(base ++ [file: file, contents: "new"])
    fu = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 19))
    assert is_binary(Proto.field(fu, 1))
    assert Proto.field(fu, 4) == "new"

    %{transaction: tx} = Transaction.file_delete(base ++ [file: file])
    fd = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 18))
    assert is_binary(Proto.field(fd, 2))
  end

  test "schedule_create wraps a SchedulableTransactionBody with cryptoTransfer at field 9" do
    key = PrivateKey.generate_ecdsa()
    from = AccountId.parse("0.0.8260469")
    to = AccountId.parse("0.0.98")

    %{transaction: tx} =
      Transaction.schedule_create(
        operator_id: from,
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        transfers: [{from, -1}, {to, 1}],
        schedule_memo: "sched"
      )

    sc = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 42))
    assert Proto.field(sc, 2) == "sched"
    # scheduledTransactionBody = 1 → SchedulableTransactionBody { cryptoTransfer = 9 }
    schedulable = Proto.decode(Proto.field(sc, 1))
    crypto = Proto.decode(Proto.field(schedulable, 9))
    # CryptoTransferTransactionBody { transfers = 1 } present
    assert is_binary(Proto.field(crypto, 1))
  end

  test "schedule_sign carries the scheduleID (field 44 / scheduleID=1)" do
    key = PrivateKey.generate_ecdsa()

    %{transaction: tx} =
      Transaction.schedule_sign(
        operator_id: AccountId.parse("0.0.2"),
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        schedule_id: ScheduleId.parse("0.0.555")
      )

    ss = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 44))
    assert is_binary(Proto.field(ss, 1))
  end

  test "contract_create encodes contractCreateInstance (8) with inline initcode + gas" do
    key = PrivateKey.generate_ecdsa()

    %{transaction: tx} =
      Transaction.contract_create(
        operator_id: AccountId.parse("0.0.2"),
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        bytecode: <<0x60, 0x00, 0x60, 0x00, 0xF3>>,
        gas: 120_000
      )

    cc = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 8))
    # initcode is field 16 of the oneof; gas is field 4
    assert Proto.field(cc, 16) == <<0x60, 0x00, 0x60, 0x00, 0xF3>>
    assert Proto.field(cc, 4) == 120_000
  end

  test "contract_call encodes contractCall (7) with contractID, gas, params" do
    key = PrivateKey.generate_ecdsa()

    %{transaction: tx} =
      Transaction.contract_call(
        operator_id: AccountId.parse("0.0.2"),
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        contract: ContractId.parse("0.0.1234"),
        gas: 60_000,
        function_parameters: <<0xAB, 0xCD>>
      )

    call = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 7))
    # ContractID sub-message (field 1), gas (2), functionParameters (4)
    assert is_binary(Proto.field(call, 1))
    assert Proto.field(call, 2) == 60_000
    assert Proto.field(call, 4) == <<0xAB, 0xCD>>
  end

  test "approve_allowance encodes cryptoApproveAllowance (48) with hbar/token/nft allowances" do
    key = PrivateKey.generate_ecdsa()
    owner = AccountId.parse("0.0.8260469")
    spender = AccountId.parse("0.0.98")
    token = TokenId.parse("0.0.777")

    %{transaction: tx} =
      Transaction.approve_allowance(
        operator_id: owner,
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        hbar_allowances: [{owner, spender, 100}],
        token_allowances: [{token, owner, spender, 50}],
        nft_allowances: [{token, owner, spender, [1, 2]}, {token, owner, spender, :all}]
      )

    body = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 48))
    # CryptoAllowance (field 1): amount = field 3
    assert Proto.field(Proto.decode(Proto.field(body, 1)), 3) == 100
    # TokenAllowance (field 3): amount = field 4
    assert Proto.field(Proto.decode(Proto.field(body, 3)), 4) == 50
    # two NftAllowances (field 2): the second is approved-for-all (field 5)
    nfts = for {2, _w, v} <- body, do: Proto.decode(v)
    assert length(nfts) == 2
    assert Proto.decode_varints(Proto.field(hd(nfts), 4)) == [1, 2]
    assert is_binary(Proto.field(List.last(nfts), 5))
  end

  test "delete_nft_allowance encodes cryptoDeleteAllowance (49) with removed serials" do
    key = PrivateKey.generate_ecdsa()

    %{transaction: tx} =
      Transaction.delete_nft_allowance(
        operator_id: AccountId.parse("0.0.2"),
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        nft_allowances: [{TokenId.parse("0.0.777"), AccountId.parse("0.0.2"), [1, 2, 3]}]
      )

    body = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 49))
    rm = Proto.decode(Proto.field(body, 2))
    assert is_binary(Proto.field(rm, 1))
    assert Proto.decode_varints(Proto.field(rm, 3)) == [1, 2, 3]
  end

  test "crypto_transfer marks an approved (allowance-based) debit via is_approval" do
    key = PrivateKey.generate_ecdsa()
    owner = AccountId.parse("0.0.8260469")
    spender = AccountId.parse("0.0.98")

    %{transaction: tx} =
      Transaction.crypto_transfer(
        operator_id: spender,
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        transfers: [{owner, -1, true}, {spender, 1}]
      )

    crypto = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 14))
    [owner_aa, spender_aa] = for {1, _w, v} <- Proto.decode(Proto.field(crypto, 1)), do: Proto.decode(v)
    # AccountAmount.is_approval = field 3 (bool): set on the owner debit, omitted on the credit
    assert Proto.field(owner_aa, 3) == 1
    assert Proto.field(spender_aa, 3) == nil
  end

  test "create_topic encodes a consensusCreateTopic body (field 24)" do
    key = PrivateKey.generate_ed25519()

    %{transaction: tx} =
      Transaction.create_topic(
        operator_id: AccountId.parse("0.0.2"),
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        memo: "trustlayer"
      )

    body = Proto.decode(Proto.field(decode_signed(tx), 1))
    assert is_binary(Proto.field(body, 24))
  end

  # --- R3.4 breadth: account lifecycle + token update/dissociate/delete -------

  defp base(key), do: [operator_id: AccountId.parse("0.0.1001"), operator_key: key, node_account_id: AccountId.parse("0.0.3")]

  test "crypto_create encodes a cryptoCreateAccount body (field 11) with key + initial balance" do
    key = PrivateKey.generate_ed25519()
    new_key = PrivateKey.generate_ecdsa() |> PrivateKey.public_key()

    %{transaction: tx} = Transaction.crypto_create(base(key) ++ [key: new_key, initial_balance: 500])

    body = Proto.decode(Proto.field(decode_signed(tx), 1))
    create = Proto.decode(Proto.field(body, 11))
    # Key { ECDSASecp256k1 = 7 } holds the new account's public key
    assert Proto.field(Proto.decode(Proto.field(create, 1)), 7) == PublicKey.to_bytes(new_key)
    assert Proto.field(create, 2) == 500
  end

  test "crypto_create defaults the key to the operator's public key" do
    key = PrivateKey.generate_ed25519()
    %{transaction: tx} = Transaction.crypto_create(base(key))

    create = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 11))
    # ed25519 key sits in Key field 2
    assert Proto.field(Proto.decode(Proto.field(create, 1)), 2) == PublicKey.to_bytes(PrivateKey.public_key(key))
  end

  test "crypto_update encodes a cryptoUpdateAccount body (field 15); only set fields are present" do
    key = PrivateKey.generate_ed25519()
    account = AccountId.parse("0.0.7777")

    %{transaction: tx} = Transaction.crypto_update(base(key) ++ [account: account, account_memo: "renamed"])

    update = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 15))
    # accountIDToUpdate = 2
    assert Proto.field(Proto.decode(Proto.field(update, 2)), 3) == 7777
    # memo StringValue = 14 -> { value = 1 }
    assert Proto.field(Proto.decode(Proto.field(update, 14)), 1) == "renamed"
    # key (3) and autoRenewPeriod (7) were not passed → absent
    assert Proto.field(update, 3) == nil
    assert Proto.field(update, 7) == nil
  end

  test "crypto_delete encodes a cryptoDelete body (field 12) with delete + transfer accounts" do
    key = PrivateKey.generate_ed25519()

    %{transaction: tx} =
      Transaction.crypto_delete(base(key) ++ [account: AccountId.parse("0.0.7777"), transfer_account: AccountId.parse("0.0.98")])

    del = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 12))
    assert Proto.field(Proto.decode(Proto.field(del, 2)), 3) == 7777
    assert Proto.field(Proto.decode(Proto.field(del, 1)), 3) == 98
  end

  test "crypto_delete defaults the transfer account to the operator" do
    key = PrivateKey.generate_ed25519()
    %{transaction: tx} = Transaction.crypto_delete(base(key) ++ [account: AccountId.parse("0.0.7777")])

    del = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 12))
    assert Proto.field(Proto.decode(Proto.field(del, 1)), 3) == 1001
  end

  test "token_update encodes a tokenUpdate body (field 36) with name/symbol/admin key" do
    key = PrivateKey.generate_ed25519()
    admin = PrivateKey.generate_ed25519() |> PrivateKey.public_key()

    %{transaction: tx} =
      Transaction.token_update(base(key) ++ [token: TokenId.parse("0.0.5555"), name: "New Name", symbol: "NEW", admin_key: admin])

    upd = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 36))
    assert Proto.field(Proto.decode(Proto.field(upd, 1)), 3) == 5555
    assert Proto.field(upd, 3) == "New Name"
    assert Proto.field(upd, 2) == "NEW"
    assert Proto.field(Proto.decode(Proto.field(upd, 5)), 2) == PublicKey.to_bytes(admin)
  end

  test "token_dissociate is a field-41 body listing every token, and supports multi-sig" do
    operator_key = PrivateKey.generate_ed25519()
    account_key = PrivateKey.generate_ecdsa()
    account = AccountId.parse("0.0.7777")

    %{transaction: tx} =
      Transaction.token_dissociate(
        base(operator_key) ++
          [account: account, tokens: [TokenId.parse("0.0.10"), TokenId.parse("0.0.11")], signers: [account_key]]
      )

    sd = decode_signed(tx)
    diss = Proto.decode(Proto.field(Proto.decode(Proto.field(sd, 1)), 41))
    # account = 1, tokens = 2 (repeated)
    assert Proto.field(Proto.decode(Proto.field(diss, 1)), 3) == 7777
    tokens = for {2, _w, v} <- diss, do: Proto.field(Proto.decode(v), 3)
    assert tokens == [10, 11]
    # operator + account both sign
    assert length(for {1, _w, v} <- Proto.decode(Proto.field(sd, 2)), do: v) == 2
  end

  test "token_delete encodes a tokenDeletion body (field 35)" do
    key = PrivateKey.generate_ed25519()
    %{transaction: tx} = Transaction.token_delete(base(key) ++ [token: TokenId.parse("0.0.5555")])

    del = Proto.decode(Proto.field(Proto.decode(Proto.field(decode_signed(tx), 1)), 35))
    assert Proto.field(Proto.decode(Proto.field(del, 1)), 3) == 5555
  end
end
