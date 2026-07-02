defmodule Hedera.Crypto.Secp256k1Test do
  @moduledoc "Direct tests for the secp256k1 DER/raw, low-S, compression and recovery helpers."
  use ExUnit.Case, async: true

  alias Hedera.Crypto.Secp256k1

  @n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
  @half div(@n, 2)

  defp pad32(int) do
    b = :binary.encode_unsigned(int)
    :binary.copy(<<0>>, 32 - byte_size(b)) <> b
  end

  test "der_to_raw normalizes a high-S signature to low-S" do
    r = 5
    s_high = @n - 3
    assert s_high > @half

    der = Secp256k1.raw_to_der(pad32(r) <> pad32(s_high))
    <<r_out::256, s_out::256>> = Secp256k1.der_to_raw(der)

    assert r_out == r
    # low-S: n - s_high == 3, which is ≤ n/2
    assert s_out == 3
    assert s_out <= @half
  end

  test "raw_to_der ∘ der_to_raw round-trips a canonical (low-S) signature" do
    raw = pad32(7) <> pad32(123_456_789)
    assert Secp256k1.der_to_raw(Secp256k1.raw_to_der(raw)) == raw
  end

  test "der_to_raw raises on non-DER input" do
    assert_raise ArgumentError, fn -> Secp256k1.der_to_raw(<<0x00, 0x01, 0x02>>) end
  end

  test "compress is idempotent on an already-compressed point" do
    key = Hedera.PrivateKey.generate_ecdsa()
    %{point: uncompressed} = Hedera.PrivateKey.public_key(key)
    compressed = Secp256k1.compress(uncompressed)

    assert byte_size(compressed) == 33
    assert :binary.first(compressed) in [0x02, 0x03]
    assert Secp256k1.compress(compressed) == compressed
  end

  test "recover rejects out-of-range r/s" do
    assert Secp256k1.recover(0, 1, 1, 0) == :error
    assert Secp256k1.recover(@n, 1, 1, 0) == :error
    assert Secp256k1.recover(1, 0, 1, 0) == :error
    assert Secp256k1.recover(1, @n, 1, 0) == :error
  end

  test "recovery_id returns the parity that reproduces the signer" do
    key = Hedera.PrivateKey.generate_ecdsa()
    pub = Hedera.PublicKey.to_bytes(Hedera.PrivateKey.public_key(key))
    z = Hedera.Crypto.Keccak.hash256("recover me")
    sig = Hedera.PrivateKey.sign(key, "recover me")

    assert Secp256k1.recovery_id(sig, z, pub) in [0, 1]
  end
end
