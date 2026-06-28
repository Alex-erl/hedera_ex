# Changelog

## 0.1.0 (unreleased) — foundation (alpha)

The cryptographic and encoding foundation, fully unit-tested offline:

- **Keccak-256** — pure Elixir (Hedera/Ethereum padding), verified against known vectors.
- **Keys** — `Hedera.PrivateKey` / `Hedera.PublicKey` for Ed25519 and ECDSA secp256k1,
  with Hedera's signing conventions (Keccak-256 prehash + canonical low-S `r‖s` for ECDSA),
  33-byte compressed public keys, sign/verify, hex round-trip.
- **Identifiers** — `AccountId`, `TopicId`, `Timestamp` (parse / format / protobuf).
- **Protobuf** — minimal proto3 wire encoder (`Hedera.Proto`).

Not yet implemented (next milestones): `TransactionBody` / Consensus Service transaction
encoding and the gRPC execution layer (require validation against a live testnet node).
