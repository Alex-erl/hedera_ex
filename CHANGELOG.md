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

### Crypto Service (HBAR transfers)

- **Transfers** — `Hedera.Transaction.crypto_transfer/1` and `Hedera.Client.transfer_hbar/3`
  build and sign a `cryptoTransfer` of HBAR between accounts. Amounts are encoded as protobuf
  `sint64` (ZigZag, via `Hedera.Proto.sint64_field/2`); debits are negative, credits positive,
  and must net to zero.
- **Validated live**: a natively-built transfer is accepted by a testnet node (pre-check `OK`)
  and reaches a `SUCCESS` receipt, confirming the `cryptoTransfer` field numbers and the
  `TransferList` / `AccountAmount` (sint64) encoding end-to-end.

### Token Service (HTS)

- **Tokens** — `Hedera.Transaction` gains `token_create/1`, `token_mint/1`, `token_burn/1` and
  `token_associate/1`; `crypto_transfer/1` now also carries `:token_transfers`. `Hedera.Client`
  gains `create_token/2`, `mint_token/4`, `burn_token/4`, `associate_token/4`, `transfer_token/4`.
  New `Hedera.TokenId`; `Hedera.PublicKey.to_key_proto/1` encodes a `Key` message (Ed25519 in
  field 2, ECDSA secp256k1 in field 7); `Hedera.Receipt` now parses `token_id` and
  `new_total_supply`.
- **Multi-signature** — transaction building accepts `:signers` (extra keys beyond the operator);
  the signature map carries one `SignaturePair` per distinct key, so e.g. a token association can
  be signed by both the fee-paying operator and the account being associated.
- **Validated live** (full lifecycle on testnet): create a fungible token → mint supply (receipt
  `token_id` + `new_total_supply`) → associate a second account (multi-sig: operator ECDSA +
  account Ed25519) → transfer tokens to it — every step reaches a `SUCCESS` receipt. This confirms
  the `tokenCreation` (29) / `tokenMint` (37) / `tokenAssociate` (40) field numbers, the `Key`
  encoding, and `TokenTransferList` end-to-end.

Next: NFT mint/metadata, token freeze/kyc/wipe, protoc-generated messages, hex.pm release.
