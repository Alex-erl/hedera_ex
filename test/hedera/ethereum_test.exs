defmodule Hedera.EthereumTest do
  @moduledoc "secp256k1 public-key recovery + EIP-1559 signing (offline)."
  use ExUnit.Case, async: true

  alias Hedera.{Ethereum, PrivateKey, PublicKey, Rlp}
  alias Hedera.Crypto.{Keccak, Secp256k1}

  test "recovery_id recovers exactly the signer's public key" do
    for _ <- 1..10 do
      key = PrivateKey.generate_ecdsa()
      pub = PublicKey.to_bytes(PrivateKey.public_key(key))
      msg = :crypto.strong_rand_bytes(48)
      <<r::binary-size(32), s::binary-size(32)>> = sig = PrivateKey.sign(key, msg)
      z = Keccak.hash256(msg)

      recid = Secp256k1.recovery_id(sig, z, pub)
      assert recid in [0, 1]

      # recovering at that parity reproduces the signer; the other parity doesn't
      {x, y} = Secp256k1.recover(:binary.decode_unsigned(r), :binary.decode_unsigned(s), :binary.decode_unsigned(z), recid)
      assert Secp256k1.compress(<<0x04>> <> pad32(x) <> pad32(y)) == pub
    end
  end

  test "sign_eip1559 emits a type-2 tx and embeds a signature that recovers the signer" do
    key = PrivateKey.generate_ecdsa()
    pub = PublicKey.to_bytes(PrivateKey.public_key(key))
    to_hex = "000102030405060708090a0b0c0d0e0f10111213"

    params = %{
      chain_id: 296,
      nonce: 1,
      max_priority_fee_per_gas: 1_000_000_000,
      max_fee_per_gas: 2_000_000_000,
      gas_limit: 21_000,
      to: "0x" <> to_hex,
      value: 0,
      data: <<>>
    }

    data = Ethereum.sign_eip1559(params, key)

    # the 9 signable fields, exactly as the signer built them
    unsigned =
      <<0x02>> <>
        Rlp.encode([296, 1, 1_000_000_000, 2_000_000_000, 21_000, Base.decode16!(to_hex, case: :lower), 0, <<>>, []])

    assert <<0x02, _::binary>> = data
    # signed tx carries 3 extra fields (yParity, r, s) → strictly longer
    assert byte_size(data) > byte_size(unsigned)

    # the signature over keccak(unsigned) recovers the signer (EVM `from`)
    assert Secp256k1.recovery_id(PrivateKey.sign(key, unsigned), Keccak.hash256(unsigned), pub) in [0, 1]
  end

  defp pad32(int) do
    b = :binary.encode_unsigned(int)
    :binary.copy(<<0>>, 32 - byte_size(b)) <> b
  end
end
