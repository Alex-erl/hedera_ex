defmodule Hedera.IdentifiersTest do
  use ExUnit.Case, async: true

  alias Hedera.{AccountId, ContractId, FileId, ScheduleId, Timestamp, TokenId, TopicId}

  test "AccountId parses, formats, and encodes" do
    a = AccountId.parse("0.0.8260469")
    assert a == %AccountId{shard: 0, realm: 0, num: 8_260_469}
    assert AccountId.to_string(a) == "0.0.8260469"
    # fields: shard=0 (0x08 0x00), realm=0 (0x10 0x00), num (0x18 ...)
    assert <<0x08, 0x00, 0x10, 0x00, 0x18, _::binary>> = AccountId.to_proto(a)
  end

  test "TopicId parses, formats, and encodes" do
    t = TopicId.parse("0.0.9339331")
    assert TopicId.to_string(t) == "0.0.9339331"
    assert <<0x08, 0x00, 0x10, 0x00, 0x18, _::binary>> = TopicId.to_proto(t)
  end

  test "TokenId parses, formats, and encodes" do
    t = TokenId.parse("0.0.1234567")
    assert t == %TokenId{shard: 0, realm: 0, num: 1_234_567}
    assert TokenId.to_string(t) == "0.0.1234567"
    assert <<0x08, 0x00, 0x10, 0x00, 0x18, _::binary>> = TokenId.to_proto(t)
  end

  test "FileId and ScheduleId parse, format, and encode" do
    f = FileId.parse("0.0.111")
    assert FileId.to_string(f) == "0.0.111"
    assert <<0x08, 0x00, 0x10, 0x00, 0x18, _::binary>> = FileId.to_proto(f)

    s = ScheduleId.parse("0.0.222")
    assert ScheduleId.to_string(s) == "0.0.222"
    assert <<0x08, 0x00, 0x10, 0x00, 0x18, _::binary>> = ScheduleId.to_proto(s)

    c = ContractId.parse("0.0.333")
    assert ContractId.to_string(c) == "0.0.333"
    assert <<0x08, 0x00, 0x10, 0x00, 0x18, _::binary>> = ContractId.to_proto(c)
  end

  test "Timestamp formats with 9-digit nanos and encodes" do
    ts = %Timestamp{seconds: 1_700_000_000, nanos: 42}
    assert Timestamp.to_string(ts) == "1700000000.000000042"
    assert <<0x08, _::binary>> = Timestamp.to_proto(ts)
  end
end
