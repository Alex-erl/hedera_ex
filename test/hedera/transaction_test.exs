defmodule Hedera.TransactionTest do
  use ExUnit.Case, async: true

  alias Hedera.{AccountId, PrivateKey, PublicKey, Proto, TokenId, TopicId, Transaction}

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
end
