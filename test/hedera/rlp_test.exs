defmodule Hedera.RlpTest do
  @moduledoc "RLP encoder against the canonical Ethereum spec vectors."
  use ExUnit.Case, async: true

  alias Hedera.Rlp

  test "byte-string vectors" do
    assert Rlp.encode("dog") == <<0x83, ?d, ?o, ?g>>
    assert Rlp.encode("") == <<0x80>>
    assert Rlp.encode(<<0x00>>) == <<0x00>>
    assert Rlp.encode(<<0x0F>>) == <<0x0F>>
    assert Rlp.encode(<<0x04, 0x00>>) == <<0x82, 0x04, 0x00>>
  end

  test "integer vectors (minimal big-endian; 0 → empty string)" do
    assert Rlp.encode(0) == <<0x80>>
    assert Rlp.encode(15) == <<0x0F>>
    assert Rlp.encode(1024) == <<0x82, 0x04, 0x00>>
  end

  test "list vectors" do
    assert Rlp.encode([]) == <<0xC0>>
    assert Rlp.encode(["cat", "dog"]) == <<0xC8, 0x83, ?c, ?a, ?t, 0x83, ?d, ?o, ?g>>
  end

  test "a >55-byte string uses the 0xb7+len-of-len long form" do
    <<prefix, len, _rest::binary>> = Rlp.encode(String.duplicate("a", 56))
    assert prefix == 0xB8
    assert len == 56
  end
end
