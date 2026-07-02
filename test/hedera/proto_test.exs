defmodule Hedera.ProtoTest do
  use ExUnit.Case, async: true

  alias Hedera.Proto
  doctest Hedera.Proto

  test "varint encodes per the protobuf spec" do
    assert Proto.varint(0) == <<0>>
    assert Proto.varint(1) == <<1>>
    assert Proto.varint(127) == <<127>>
    assert Proto.varint(128) == <<0x80, 0x01>>
    assert Proto.varint(300) == <<0xAC, 0x02>>
  end

  test "varint_field tags with wire type 0" do
    # field 1, wire 0 -> tag 0x08
    assert Proto.varint_field(1, 5) == <<0x08, 5>>
    assert Proto.varint_field(3, 123) == <<0x18, 123>>
  end

  test "bytes_field tags with wire type 2 and a length prefix" do
    # field 2, wire 2 -> tag 0x12
    assert Proto.bytes_field(2, "hi") == <<0x12, 0x02, ?h, ?i>>
  end

  test "maybe_bytes_field omits nil" do
    assert Proto.maybe_bytes_field(1, nil) == <<>>
    assert Proto.maybe_bytes_field(1, "x") == <<0x0A, 0x01, ?x>>
  end
end
