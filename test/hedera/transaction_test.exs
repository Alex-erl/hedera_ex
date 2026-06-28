defmodule Hedera.TransactionTest do
  use ExUnit.Case, async: true

  alias Hedera.{AccountId, PrivateKey, PublicKey, Proto, TopicId, Transaction}

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
