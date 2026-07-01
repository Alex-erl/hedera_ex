defmodule Hedera.ReceiptTest do
  use ExUnit.Case, async: true

  alias Hedera.{Proto, Receipt, TokenId, TopicId}

  test "parses status, topic id, sequence number and running hash" do
    bytes =
      Proto.varint_field(1, 22) <>
        Proto.bytes_field(6, TopicId.to_proto(%TopicId{shard: 0, realm: 0, num: 5})) <>
        Proto.varint_field(7, 42) <>
        Proto.bytes_field(8, <<1, 2, 3>>)

    receipt = Receipt.parse(bytes)

    assert receipt.status == 22
    assert Receipt.success?(receipt)
    assert Receipt.final?(receipt)
    assert receipt.topic_sequence_number == 42
    assert receipt.topic_id == %TopicId{shard: 0, realm: 0, num: 5}
    assert receipt.topic_running_hash == <<1, 2, 3>>
  end

  test "UNKNOWN status is not final" do
    refute Receipt.final?(Receipt.parse(Proto.varint_field(1, 21)))
  end

  test "parses token id (create) and new total supply (mint/burn)" do
    bytes =
      Proto.varint_field(1, 22) <>
        Proto.bytes_field(10, TokenId.to_proto(%TokenId{shard: 0, realm: 0, num: 777})) <>
        Proto.varint_field(11, 1_000)

    receipt = Receipt.parse(bytes)

    assert Receipt.success?(receipt)
    assert receipt.token_id == %TokenId{shard: 0, realm: 0, num: 777}
    assert receipt.new_total_supply == 1_000
  end
end
