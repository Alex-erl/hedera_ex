defmodule Hedera.PbEquivalenceTest do
  @moduledoc """
  Proves the protoc-generated `Hedera.Pb.*` modules are wire-compatible with the
  hand-rolled encoder/decoder in BOTH directions. This is the safety net for
  migrating the wire layer off hand-rolled `Hedera.Proto` calls: as long as these
  pass, generated structs and the hand-rolled path produce mutually-decodable
  bytes. (They are not byte-identical: proto3 omits zero-valued fields while the
  hand-rolled encoder emits e.g. shard/realm 0 explicitly — both are valid
  protobuf and decode to the same values.)
  """
  use ExUnit.Case, async: true

  alias Hedera.{AccountId, PrivateKey, Proto, Receipt, TopicId, Transaction}
  alias Hedera.Pb

  defp bodybytes(tx) do
    # Transaction { signedTransactionBytes = 5 } -> SignedTransaction { bodyBytes = 1 }
    signed = Proto.field(Proto.decode(tx), 5)
    Proto.field(Proto.decode(signed), 1)
  end

  test "generated TransactionBody decodes hand-rolled submit_message bytes" do
    key = PrivateKey.generate_ecdsa()

    %{transaction: tx} =
      Transaction.submit_message(
        operator_id: AccountId.parse("0.0.8260469"),
        operator_key: key,
        node_account_id: AccountId.parse("0.0.3"),
        topic_id: TopicId.parse("0.0.9339331"),
        message: "hello-proto"
      )

    body = Pb.TransactionBody.decode(bodybytes(tx))

    assert body.transactionFee == 200_000_000
    assert body.nodeAccountID.accountNum == 3
    assert body.transactionID.accountID.accountNum == 8_260_469
    assert {:consensusSubmitMessage, submit} = body.data
    assert submit.message == "hello-proto"
    assert submit.topicID.topicNum == 9_339_331
  end

  test "hand-rolled Proto.decode reads generated-encoded TransactionBody" do
    gen = %Pb.TransactionBody{
      transactionID: %Pb.TransactionID{
        accountID: %Pb.AccountID{accountNum: 8_260_469},
        transactionValidStart: %Pb.Timestamp{seconds: 1_700_000_000, nanos: 5}
      },
      nodeAccountID: %Pb.AccountID{accountNum: 3},
      transactionFee: 200_000_000,
      data:
        {:consensusSubmitMessage,
         %Pb.ConsensusSubmitMessageTransactionBody{
           topicID: %Pb.TopicID{topicNum: 9_339_331},
           message: "from-generated"
         }}
    }

    bin = gen |> Pb.TransactionBody.encode() |> IO.iodata_to_binary()
    decoded = Proto.decode(bin)

    assert Proto.field(decoded, 3) == 200_000_000
    # consensusSubmitMessage is field 27 in TransactionBody
    submit = Proto.decode(Proto.field(decoded, 27))
    assert Proto.field(submit, 2) == "from-generated"
  end

  test "generated and hand-rolled agree on sint64 (ZigZag) transfer amounts" do
    gen = %Pb.CryptoTransferTransactionBody{
      transfers: %Pb.TransferList{
        accountAmounts: [
          %Pb.AccountAmount{accountID: %Pb.AccountID{accountNum: 8_260_469}, amount: -5},
          %Pb.AccountAmount{accountID: %Pb.AccountID{accountNum: 98}, amount: 5}
        ]
      }
    }

    bin = gen |> Pb.CryptoTransferTransactionBody.encode() |> IO.iodata_to_binary()

    # generated decode recovers the signed values
    [a, b] = Pb.CryptoTransferTransactionBody.decode(bin).transfers.accountAmounts
    assert a.amount == -5
    assert b.amount == 5

    # hand-rolled decode sees the raw ZigZag varints (-5 -> 9, +5 -> 10)
    tl = Proto.decode(Proto.field(Proto.decode(bin), 1))
    raw = for {1, _w, v} <- tl, do: Proto.field(Proto.decode(v), 2)
    assert raw == [9, 10]
  end

  test "generated TransactionReceipt matches Hedera.Receipt.parse" do
    bin =
      Proto.varint_field(1, 22) <>
        Proto.bytes_field(6, TopicId.to_proto(%TopicId{shard: 0, realm: 0, num: 5})) <>
        Proto.varint_field(7, 42) <>
        Proto.bytes_field(8, <<1, 2, 3>>)

    pb = Pb.TransactionReceipt.decode(bin)
    r = Receipt.parse(bin)

    assert pb.status == 22 and r.status == 22
    assert pb.topicSequenceNumber == 42 and r.topic_sequence_number == 42
    assert pb.topicID.topicNum == 5 and r.topic_id.num == 5
    assert pb.topicRunningHash == <<1, 2, 3>> and r.topic_running_hash == <<1, 2, 3>>
  end
end
