# Sign an EIP-1559 (type-2) Ethereum transaction natively — no network, no creds.
#   mix run examples/eip1559_offline.exs
alias Hedera.{Ethereum, PrivateKey, PublicKey}
alias Hedera.Crypto.{Keccak, Secp256k1}

signer = PrivateKey.generate_ecdsa()

data =
  Ethereum.sign_eip1559(
    %{
      chain_id: 296,
      nonce: 0,
      max_priority_fee_per_gas: 1_000_000_000,
      max_fee_per_gas: 2_000_000_000,
      gas_limit: 21_000,
      to: "0x000102030405060708090a0b0c0d0e0f10111213",
      value: 0,
      data: <<>>
    },
    signer
  )

IO.puts("signed ethereum_data (#{byte_size(data)} bytes):")
IO.puts("0x" <> Base.encode16(data, case: :lower))
IO.puts("type byte: 0x#{Base.encode16(binary_part(data, 0, 1))}  (0x02 = EIP-1559)")

# The embedded signature recovers to the signer's key (the EVM `from` address).
unsigned =
  <<0x02>> <>
    Hedera.Rlp.encode([
      296, 0, 1_000_000_000, 2_000_000_000, 21_000,
      Base.decode16!("000102030405060708090a0b0c0d0e0f10111213", case: :lower),
      0, <<>>, []
    ])

pub = PublicKey.to_bytes(PrivateKey.public_key(signer))
parity = Secp256k1.recovery_id(PrivateKey.sign(signer, unsigned), Keccak.hash256(unsigned), pub)
IO.puts("recovered yParity: #{parity}  (signature verifies against the signer)")
