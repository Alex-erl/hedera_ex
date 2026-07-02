# Ethereum (EIP-1559) transactions

Hedera runs the EVM: a signed Ethereum transaction can be **relayed** to Hedera
and executed against the sender's EVM address. `hedera_ex` builds and signs
**EIP-1559 (type-2)** transactions natively — RLP encoding, `keccak256` signing,
and secp256k1 public-key recovery for `yParity` — with no external Ethereum
dependency.

## Sign

```elixir
alias Hedera.{Ethereum, PrivateKey}

signer = PrivateKey.from_string_ecdsa(System.fetch_env!("EVM_KEY"))

ethereum_data =
  Ethereum.sign_eip1559(
    %{
      chain_id: 296,                       # Hedera testnet (mainnet is 295)
      nonce: 0,
      max_priority_fee_per_gas: 1_000_000_000,
      max_fee_per_gas: 2_000_000_000,
      gas_limit: 21_000,
      to: "0x000102030405060708090a0b0c0d0e0f10111213",
      value: 0,
      data: <<>>                           # or "0x..." ABI-encoded call data
    },
    signer
  )
```

`ethereum_data` is the complete signed transaction: `0x02 ‖ rlp([chainId, nonce,
maxPriorityFeePerGas, maxFeePerGas, gasLimit, to, value, data, accessList,
yParity, r, s])`. `to` may be a 20-byte binary, a `"0x…"` hex string, or absent
(contract creation). `sign_eip1559/2` raises `ArgumentError` on invalid params.

## Relay

```elixir
{:ok, result} =
  Client.send_ethereum_transaction(client, ethereum_data, max_gas_allowance: 100_000)
```

The operator is the Hedera-side payer; the embedded Ethereum signature authorizes
the EVM call. `:max_gas_allowance` (tinybars) is what the payer will cover if the
Ethereum sender can't. For large call data, store it in a file and pass
`:call_data` (a `FileId`) instead of inlining it.

## Under the hood

- `Hedera.Rlp` — a minimal RLP encoder (integers → minimal big-endian, `0` → the
  empty string; see its doctests).
- `Hedera.Crypto.Secp256k1.recovery_id/3` — recovers the signer's public key to
  determine `yParity`. OTP has no `ecrecover`, so recovery is implemented with
  secp256k1 point arithmetic over `F_p` (the prime is `≡ 3 mod 4`, so the modular
  square root is `a^((p+1)/4)`).
- The signing hash is `keccak256(0x02 ‖ rlp([...9 fields]))` — identical to what
  Hedera's ECDSA path produces, so `PrivateKey.sign/2` yields the exact signature
  Ethereum expects.
