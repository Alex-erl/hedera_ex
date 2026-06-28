defmodule Hedera.KeysTest do
  use ExUnit.Case, async: true

  alias Hedera.{PrivateKey, PublicKey}

  @n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
  @half div(@n, 2)
  @msg "trustlayer audit anchor"

  describe "Ed25519" do
    test "signs and verifies; rejects a wrong message" do
      key = PrivateKey.generate_ed25519()
      pub = PrivateKey.public_key(key)
      sig = PrivateKey.sign(key, @msg)

      assert byte_size(sig) == 64
      assert PublicKey.verify(pub, @msg, sig)
      refute PublicKey.verify(pub, "tampered", sig)
    end

    test "round-trips through hex" do
      key = PrivateKey.generate_ed25519()
      assert PrivateKey.from_string_ed25519(PrivateKey.to_string(key)).bytes == key.bytes
    end
  end

  describe "ECDSA secp256k1 (Hedera convention)" do
    test "signs (keccak prehash) and verifies; rejects a wrong message" do
      key = PrivateKey.generate_ecdsa()
      pub = PrivateKey.public_key(key)
      sig = PrivateKey.sign(key, @msg)

      assert byte_size(sig) == 64
      assert PublicKey.verify(pub, @msg, sig)
      refute PublicKey.verify(pub, "tampered", sig)
    end

    test "produces a low-S signature" do
      key = PrivateKey.generate_ecdsa()
      <<_r::binary-size(32), s::binary-size(32)>> = PrivateKey.sign(key, @msg)
      assert :binary.decode_unsigned(s) <= @half
    end

    test "public key serializes to a 33-byte compressed point" do
      pub = PrivateKey.generate_ecdsa() |> PrivateKey.public_key()
      wire = PublicKey.to_bytes(pub)
      assert byte_size(wire) == 33
      assert :binary.first(wire) in [0x02, 0x03]
    end
  end
end
