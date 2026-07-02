# Cryptography

`hedera_ex` implements Hedera's signing conventions directly on OTP `:crypto`,
with pure-Elixir Keccak-256 and secp256k1 helpers where OTP falls short.

## Key types

| Type | Sign input | Signature | Public key on the wire |
|------|-----------|-----------|------------------------|
| **Ed25519** | message bytes | 64-byte EdDSA | 32-byte point |
| **ECDSA secp256k1** | **Keccak-256** of the message | 64-byte `r ‖ s`, **low-S** | 33-byte compressed point |

```elixir
alias Hedera.{PrivateKey, PublicKey}

key = PrivateKey.generate_ecdsa()
sig = PrivateKey.sign(key, "audit event hash")     # 64 bytes, low-S
PublicKey.verify(PrivateKey.public_key(key), "audit event hash", sig)   #=> true
```

`verify/3` returns `false` for a wrong-size or malformed signature — it never
raises.

## The Hedera ECDSA convention

- **Keccak-256 prehash** (Ethereum's padding, *not* SHA3-256 — `Hedera.Crypto.Keccak`).
- **Canonical low-S**: `s` is normalized to the lower half of the curve order
  (required by Hedera and Ethereum). `Hedera.Crypto.Secp256k1.der_to_raw/1`
  converts OpenSSL's DER output to the 64-byte `r ‖ s` form and enforces low-S.
- **Compressed public keys**: 33 bytes (`0x02`/`0x03` ‖ x) on the wire.

This is why the same secp256k1 key signs both Hedera transactions and Ethereum
(EIP-1559) transactions — see the [Ethereum guide](ethereum.md).

## Secret handling

`%Hedera.PrivateKey{}` has a redacting `Inspect` implementation:

```elixir
inspect(PrivateKey.generate_ed25519())
#=> "#Hedera.PrivateKey<ed25519 [redacted]>"
```

so a private key can't leak through `Logger`, a crash dump, or an accidental
`IO.inspect`. `PrivateKey.to_string/1` still returns the raw hex when you
explicitly ask for it — treat that value as a secret.

## Public-key recovery

`Hedera.Crypto.Secp256k1` implements ECDSA public-key recovery
(`recover/4`, `recovery_id/3`) with secp256k1 point arithmetic over `F_p`, since
OTP has no `ecrecover`. It's used to derive the EIP-1559 `yParity`; recovery is a
verification step over an already-secure OTP signature, so it introduces no
nonce/`k` handling of its own.
