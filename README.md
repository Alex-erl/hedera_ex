# Hedera (hedera_ex)

A **native Elixir SDK for the [Hedera](https://hedera.com) network** — keys, identifiers,
protobuf encoding, and (incrementally) the Consensus Service. No NIFs for the core crypto;
no Java/Python bridge.

> **Status: alpha.** The cryptographic and encoding foundation is implemented and unit-tested
> offline (see below). Transaction assembly and the gRPC execution layer are the next
> milestones and require validation against a live testnet node before they can be trusted.

It exists because the Elixir ecosystem has no maintained Hedera SDK — projects that need
on-chain anchoring from the BEAM currently shell out to the Python/Java SDKs. This library
brings the hard parts (Hedera's exact signing conventions) into pure, tested Elixir.

## What works today (tested, offline)

| Area | Module(s) | Notes |
|------|-----------|-------|
| Keccak-256 | `Hedera.Crypto.Keccak` | Pure Elixir; the Ethereum/Hedera padding (not SHA3). Matches known vectors. |
| Ed25519 keys | `Hedera.PrivateKey`, `Hedera.PublicKey` | Generate, sign, verify, hex round-trip. |
| ECDSA secp256k1 keys | same | Hedera convention: **Keccak-256 prehash**, canonical **low-S** 64-byte `r‖s`, 33-byte compressed public key. |
| Identifiers | `Hedera.AccountId`, `Hedera.TopicId`, `Hedera.Timestamp` | Parse / format / protobuf-encode. |
| Protobuf | `Hedera.Proto` | Minimal proto3 wire encoder (varints, length-delimited fields). |

```elixir
alias Hedera.{PrivateKey, PublicKey}

key = PrivateKey.generate_ecdsa()           # or generate_ed25519/0
pub = PrivateKey.public_key(key)

sig = PrivateKey.sign(key, "audit-event-hash")
true = PublicKey.verify(pub, "audit-event-hash", sig)

PublicKey.to_string(pub)                     # 33-byte compressed (ECDSA) hex
```

## Roadmap

- [x] Keccak-256, Ed25519 + ECDSA secp256k1 (Hedera conventions), identifiers, protobuf primitives
- [ ] `TransactionBody` + `SignedTransaction` + `Transaction` encoding (HCS create / submit)
- [ ] gRPC client over HTTP/2 to consensus nodes (`createTopic`, `submitMessage`, receipt query)
- [ ] Mirror-node REST helpers
- [ ] Token Service (HTS), account create/transfer
- [ ] protoc-generated message modules from the canonical Hedera `.proto` files

### Why field numbers aren't guessed

The transaction layer encodes Hedera protobuf messages whose field numbers must match the
canonical schema exactly. Rather than ship unverified guesses, that layer lands together with
the gRPC path so it can be validated end-to-end against a real testnet node.

## Tests

```bash
mix test          # offline; deterministic, no network
```

## License

MIT — see [LICENSE](LICENSE).
