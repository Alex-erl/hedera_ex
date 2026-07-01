defmodule Hedera.ReceiptTest do
  use ExUnit.Case, async: true

  alias Hedera.{ContractId, FileId, Proto, Receipt, ScheduleId, TokenId, TopicId}

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

  test "parses NFT mint serial numbers (packed and unpacked field 14)" do
    # unpacked: two separate field-14 varints
    unpacked = Proto.varint_field(1, 22) <> Proto.varint_field(14, 1) <> Proto.varint_field(14, 2)
    assert Receipt.parse(unpacked).serial_numbers == [1, 2]

    # packed: one length-delimited field-14 holding concatenated varints
    packed = Proto.varint_field(1, 22) <> Proto.bytes_field(14, <<3, 4, 5>>)
    assert Receipt.parse(packed).serial_numbers == [3, 4, 5]
  end

  test "parses file id (field 3) and schedule id (field 12)" do
    bytes =
      Proto.varint_field(1, 22) <>
        Proto.bytes_field(3, FileId.to_proto(%FileId{shard: 0, realm: 0, num: 111})) <>
        Proto.bytes_field(12, ScheduleId.to_proto(%ScheduleId{shard: 0, realm: 0, num: 222}))

    receipt = Receipt.parse(bytes)
    assert receipt.file_id == %FileId{shard: 0, realm: 0, num: 111}
    assert receipt.schedule_id == %ScheduleId{shard: 0, realm: 0, num: 222}
  end

  test "parses contract id from the ContractID oneof (field 4 / contractNum)" do
    # ContractID { shardNum=1..realmNum=2..contractNum=3 } as receipt field 4
    contract_id = Proto.varint_field(1, 0) <> Proto.varint_field(2, 0) <> Proto.varint_field(3, 1234)
    bytes = Proto.varint_field(1, 22) <> Proto.bytes_field(4, contract_id)

    assert Receipt.parse(bytes).contract_id == %ContractId{shard: 0, realm: 0, num: 1234}
  end
end
