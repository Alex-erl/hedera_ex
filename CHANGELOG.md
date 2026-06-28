# Changelog

## 0.1.0 (unreleased) — foundation (alpha)

The cryptographic and encoding foundation, fully unit-tested offline:

- **Keccak-256** — pure Elixir (Hedera/Ethereum padding), verified against known vectors.
- **Keys** — `Hedera.PrivateKey` / `Hedera.PublicKey` for Ed25519 and ECDSA secp256k1,
  with Hedera's signing conventions (Keccak-256 prehash + canonical low-S `r‖s` for ECDSA),
  33-byte compressed public keys, sign/verify, hex round-trip.
- **Identifiers** — `AccountId`, `TopicId`, `Timestamp` (parse / format / protobuf).
- **Protobuf** — minimal proto3 wire encoder (`Hedera.Proto`).

### Consensus Service (transactions + gRPC)

- **Transactions** — `Hedera.Transaction` encodes and signs `TransactionBody` →
  `SignedTransaction` → `Transaction` for `consensusSubmitMessage` and `consensusCreateTopic`.
- **gRPC** — `Hedera.Grpc` (unary over HTTP/2 h2c via Mint), `Hedera.Network` (testnet/mainnet
  nodes), `Hedera.Client` (`submit_message/3`, `create_topic/2`).
- **Validated live**: a natively-built, natively-signed HCS message submit is accepted by a
  Hedera **testnet** node (pre-check `OK`), confirming protobuf field numbers and signing
  end-to-end. (`mix test --include network`.)

### Receipts & mirror node

- **Receipts** — `Hedera.Client.transaction_receipt/3` polls the free gRPC
  `getTransactionReceipts`; `Hedera.Receipt` parses status, topic sequence number and running
  hash. Verified live (submit → SUCCESS receipt with a sequence number).
- **Mirror node** — `Hedera.MirrorNode` REST reads (topic messages, transactions); adds `jason`.

### Reliability

- **Address book + retry** — `Hedera.Network.testnet_nodes/0` lists multiple consensus nodes;
  `Hedera.Client` rebuilds + re-signs per target node and retries the next node on transient
  (BUSY) pre-checks or transport errors.

Next: HTS / crypto transfers, protoc-generated messages, hex.pm release.
