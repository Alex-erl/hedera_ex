# Hedera (hedera_ex)

A **native Elixir SDK for the [Hedera](https://hedera.com) network** — keys, identifiers,
protobuf encoding, and (incrementally) the Consensus Service. No NIFs for the core crypto;
no Java/Python bridge.

> **Status: alpha — but it talks to the network.** The crypto/encoding foundation is unit-tested
> offline, and **building, signing and submitting a Consensus Service message has been validated
> against the live Hedera testnet** (the node accepts the natively-signed transaction). APIs may
> still change; receipt queries and broader services are next.

It exists because the Elixir ecosystem has no maintained Hedera SDK — projects that need
on-chain anchoring from the BEAM currently shell out to the Python/Java SDKs. This library
brings the hard parts (Hedera's exact signing conventions and protobuf/gRPC wire format) into
pure, tested Elixir.

## What works today

| Area | Module(s) | Notes |
|------|-----------|-------|
| Keccak-256 | `Hedera.Crypto.Keccak` | Pure Elixir; the Ethereum/Hedera padding (not SHA3). Matches known vectors. |
| Ed25519 keys | `Hedera.PrivateKey`, `Hedera.PublicKey` | Generate, sign, verify, hex round-trip. |
| ECDSA secp256k1 keys | same | Hedera convention: **Keccak-256 prehash**, canonical **low-S** 64-byte `r‖s`, 33-byte compressed public key. |
| Identifiers | `Hedera.AccountId`, `Hedera.TopicId`, `Hedera.Timestamp`, `Hedera.TransactionId`, `Hedera.Duration` | Parse / format / protobuf-encode. |
| Protobuf | `Hedera.Proto` | Minimal proto3 wire encoder + decoder. |
| Transactions | `Hedera.Transaction` | Encode + sign `TransactionBody` → `SignedTransaction` → `Transaction` for HCS create / submit. |
| gRPC | `Hedera.Grpc`, `Hedera.Client`, `Hedera.Network` | Unary calls over HTTP/2 (h2c) to consensus nodes; **HCS message submit verified live on testnet**. |

```elixir
alias Hedera.{AccountId, Client, PrivateKey, TopicId}

client =
  Client.testnet(
    AccountId.parse("0.0.8260469"),
    PrivateKey.from_string_ecdsa(System.fetch_env!("OPERATOR_KEY"))
  )

{:ok, %{precheck_code: 0, ok?: true}} =
  Client.submit_message(client, TopicId.parse("0.0.9339331"), "audit-event-hash")
```

Run the live test yourself:

```bash
OPERATOR_ID=0.0.x OPERATOR_KEY=0x... mix test --include network
```

## Roadmap

- [x] Keccak-256, Ed25519 + ECDSA secp256k1 (Hedera conventions), identifiers, protobuf primitives
- [x] `TransactionBody` + `SignedTransaction` + `Transaction` encoding (HCS create / submit)
- [x] gRPC client over HTTP/2 (`submitMessage`, `createTopic`) — validated live on testnet
- [ ] Receipt queries (sequence number / new topic id) via gRPC or mirror node
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
