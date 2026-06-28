defmodule Hedera.Crypto.KeccakTest do
  use ExUnit.Case, async: true

  alias Hedera.Crypto.Keccak

  defp hex(b), do: Base.encode16(b, case: :lower)

  test "matches known Keccak-256 vectors" do
    assert hex(Keccak.hash256("")) ==
             "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"

    assert hex(Keccak.hash256("abc")) ==
             "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
  end

  test "differs from SHA3-256 (different padding)" do
    refute Keccak.hash256("abc") == :crypto.hash(:sha3_256, "abc")
  end

  test "handles inputs spanning multiple rate blocks" do
    # > 136 bytes exercises multi-block absorption
    big = String.duplicate("x", 200)
    assert byte_size(Keccak.hash256(big)) == 32
  end
end
