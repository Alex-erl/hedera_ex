# Hedera (hedera_ex)

[![Hex.pm](https://img.shields.io/hexpm/v/hedera_ex.svg)](https://hex.pm/packages/hedera_ex)
[![Docs](https://img.shields.io/badge/hex-docs-8e44ad.svg)](https://hexdocs.pm/hedera_ex)
[![License: MIT](https://img.shields.io/hexpm/l/hedera_ex.svg)](https://github.com/Alex-erl/hedera_ex/blob/main/LICENSE)

A **native Elixir SDK for the [Hedera](https://hedera.com) network** — keys, identifiers,
protoc-generated protobuf, gRPC, and the Consensus, Crypto, Token (incl. NFTs), File,
Schedule and Smart Contract services. No NIFs for the core crypto; no Java/Python bridge.

## Installation

Add `hedera_ex` to your deps in `mix.exs`:

```elixir
def deps do
  [{:hedera_ex, "~> 0.4.0"}]
end
```

> **Status: alpha — but it talks to the network.** The crypto/encoding foundation is unit-tested
> offline, and **building, signing and submitting transactions has been validated against the live
> Hedera testnet** (the node accepts the natively-signed transactions and returns SUCCESS receipts).
> APIs may still change.

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
| Wire encoding | `Hedera.Pb.*` (protoc-generated) | `Hedera.Transaction` builds every body as a generated struct; `priv/protos` + `generate.sh`. |
| Transactions | `Hedera.Transaction` | Build + sign `TransactionBody` → `SignedTransaction` → `Transaction`. **Multi-signature** via `:signers`. |
| Consensus Service | `submit_message/3`, `create_topic/2` | Create topics, submit messages (HCS). **Verified live.** |
| Crypto Service | `transfer_hbar/3` | HBAR transfers (`sint64`/ZigZag; must net to zero). **Verified live.** |
| Token Service (HTS) | `create_token/2`, `mint_token/4`, `burn_token/4`, `associate_token/4`, `transfer_token/4`, `transfer_nft/4`, `freeze_token`/`unfreeze_token`, `grant_kyc`/`revoke_kyc`, `wipe_token`, `pause_token`/`unpause_token` | Fungible **and NFT** create / mint (metadata) / transfer, plus freeze / KYC / wipe / pause management. **Full lifecycle verified live.** |
| File Service | `create_file/2`, `append_file/4`, `update_file/3`, `delete_file/2` | **Verified live.** |
| Schedule Service | `create_schedule/2`, `sign_schedule/3` | Scheduled transfers + multi-sig collection. **Verified live.** |
| Smart Contract Service | `create_contract/2`, `call_contract/3` | Deploy (inline bytecode or file) + call. **Verified live.** |
| Allowances | `approve_allowance/2`, `delete_nft_allowance/2` | Delegated spend (HBAR / token / NFT) + `is_approval` transfers. **Verified live.** |
| gRPC | `Hedera.Grpc`, `Hedera.Client`, `Hedera.Network` | Unary calls over HTTP/2 (h2c); multi-node address book + cross-node retry. |
| Receipts | `transaction_receipt/3`, `Hedera.Receipt` | Poll `getTransactionReceipts` → status, topic seq / hash, token / file / schedule / contract id, new total supply, NFT serials. **Verified live.** |
| Mirror node | `Hedera.MirrorNode` | REST reads (topic messages, transactions). |

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

- [x] Keccak-256, Ed25519 + ECDSA secp256k1 (Hedera conventions), identifiers, crypto primitives
- [x] Transaction encoding + signing, incl. **multi-signature** (`:signers`)
- [x] gRPC client over HTTP/2; node address book + cross-node retry on transient (BUSY) failures
- [x] Consensus Service — create topic, submit message (verified live)
- [x] Crypto Service — HBAR transfers (verified live)
- [x] Token Service (HTS) — fungible **and NFT** create / mint / burn / associate / transfer, plus freeze / KYC / wipe / pause (verified live)
- [x] File Service — create / append / update / delete (verified live)
- [x] Schedule Service — create / sign (verified live)
- [x] Smart Contract Service — create / call (verified live); call results read via mirror node
- [x] Receipts + Mirror-node REST helpers (`Hedera.MirrorNode`)
- [x] **protoc-generated wire layer** — transactions, receipts and the query/response envelope
- [x] hex.pm release
- [x] Allowances — approve / delete + `is_approval` transfers (delegated spend), verified live
- [ ] Native (gRPC) paid queries: contract-call return via record query, account balance / info, `contractCallLocal`
- [ ] Account create / update / delete; token update / dissociate
- [ ] Ethereum (EIP-1559) transactions

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
