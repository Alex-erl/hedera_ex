# Changelog

## 0.6.0 — 2026-07-02

### Ethereum (EIP-1559) + native crypto queries

- **Ethereum transactions** — `Hedera.Ethereum.sign_eip1559/2` RLP-encodes a
  type-2 transaction (new `Hedera.Rlp` encoder), signs `keccak256` of it with a
  secp256k1 key, and **recovers the `yParity`** to produce the complete signed
  `ethereum_data`. Public-key recovery is implemented natively in
  `Hedera.Crypto.Secp256k1` (secp256k1 point arithmetic over F_p; OTP has no
  `ecrecover`). `Hedera.Client.send_ethereum_transaction/3` /
  `Hedera.Transaction.ethereum/1` relay it via `EthereumTransaction` (oneof 50,
  `SmartContractService/callEthereum`).
- **Queries** — `Hedera.Client.account_balance/2` (free `CryptoGetAccountBalance`:
  hbar + token balances) and `account_info/3` (paid `CryptoGetInfo`: the query
  payment is a signed CryptoTransfer to the node). Query/Response oneofs
  `cryptogetAccountBalance` = 7, `cryptoGetInfo` = 9.
- 71 offline tests (+11: RLP vectors, secp256k1 recovery round-trip, EIP-1559
  signing, query wire contracts) + live `:network` balance/info.

## 0.5.0 — 2026-07-02

### Account lifecycle + token admin breadth

- **Crypto Service** — `Hedera.Client.create_account/2`, `update_account/3`,
  `delete_account/3` (`Hedera.Transaction.crypto_create/1` / `crypto_update/1` /
  `crypto_delete/1`; `cryptoCreateAccount` = 11, `cryptoDelete` = 12,
  `cryptoUpdateAccount` = 15). Create sets the key / initial balance and returns
  the **new account id in the receipt** (`Hedera.Receipt.account_id`, receipt
  field 2). Update touches only the fields you pass (`StringValue` / `BoolValue`
  wrappers distinguish unset from empty). Delete sweeps the balance to a transfer
  account.
- **Token Service** — `update_token/3`, `dissociate_token/4`, `delete_token/2`
  (`tokenUpdate` = 36, `tokenDissociate` = 41, `tokenDeletion` = 35).
- Wire layer: added the bodies + `StringValue` to `priv/protos` and regenerated
  `Hedera.Pb.*`. All field numbers are canonical HAPI values. 60 offline tests
  (+9); a live account create→delete round-trip test is included (`:network`).

## 0.4.0 — 2026-07-02

### Allowances (delegated spend)

- `Hedera.Client.approve_allowance/2` — HBAR, fungible-token and NFT allowances
  (per-serial or approve-for-all) — and `delete_nft_allowance/2`
  (`Hedera.Transaction.approve_allowance/1` / `delete_nft_allowance/1`;
  `cryptoApproveAllowance` = 48, `cryptoDeleteAllowance` = 49).
- Transfers take an `is_approval` flag on a debit — `{account, amount, true}`
  (HBAR/token) or `{sender, receiver, serial, true}` (NFT) — so a **spender can
  move the owner's assets under an allowance without the owner's key**.
- **Validated live**: the operator approves the client as spender; the client
  then moves the operator's HBAR via the allowance — `SUCCESS`.

## 0.3.0 — 2026-07-01

- **gRPC query/response now uses generated modules too** — the free receipt
  query and the submit pre-check are built/parsed via the generated `Hedera.Pb.*`
  query/response modules (`Hedera.Receipt.from_pb/1` maps the decoded receipt).
  `Hedera.Proto` is no longer on any live code path. Re-validated live (full
  network suite).
- **Read a contract's return value** — `Hedera.MirrorNode.contract_result/2`
  fetches a call's result from the transaction record (`call_result`, `gas_used`,
  `error_message`) via the mirror node, the payment-free read path (the value is
  not in the receipt).

## 0.2.0 — 2026-07-01

### Smart Contract Service

- `Hedera.Client.create_contract/2` and `call_contract/3`
  (`Hedera.Transaction.contract_create/1` / `contract_call/1`), with
  `Hedera.ContractId` and `contract_id` on the receipt. `contract_create`
  accepts inline `:bytecode` (EVM init) or a bytecode `:file`, plus `:gas`,
  `:admin_key`, `:constructor_parameters`, `:initial_balance`. **Validated live**:
  deploy inline bytecode → `SUCCESS` + contract id → call the contract → `SUCCESS`
  (`contractCreateInstance = 8`, `contractCall = 7`; return values live in the
  record, not the receipt — reading them is a follow-up).

### protoc-generated wire layer (migration complete)

- Vendored the subset of the HAPI protobufs `hedera_ex` uses
  (`priv/protos/hedera_min.proto`, canonical field numbers) and generate Elixir
  modules under `Hedera.Pb.*` via `protoc` + `protoc-gen-elixir`
  (`priv/protos/generate.sh`). Adds the `protobuf` dependency.
- **`Hedera.Transaction` now builds and encodes every transaction from generated
  structs, and `Hedera.Receipt` decodes via the generated `TransactionReceipt`** —
  hand-rolled field-by-field encoding is gone from the transaction/receipt layer.
  (The generated encoder is proto3-canonical: it omits zero-valued fields and
  packs repeated scalars, e.g. NFT `serialNumbers`.)
- An equivalence test pins the generated modules as wire-compatible with the
  original hand-rolled encoder in both directions (submit-message bytes,
  generated↔`Hedera.Proto` decode, ZigZag `sint64`, receipts). The full
  transaction suite — HCS / Crypto / HTS / NFT / File / Schedule — was
  **re-validated live on testnet** after the migration (all `SUCCESS`).
  (`Hedera.Proto` remains for the small gRPC query/response framing.)

### File Service

- `Hedera.Client.create_file/2`, `append_file/4`, `update_file/3`, `delete_file/2`
  (`Hedera.Transaction.file_create/1` etc.), with `Hedera.FileId` and `file_id` on the receipt.
  Files carry a `KeyList` (defaults to the operator's key → mutable). **Validated live**:
  create → append → update → delete, all `SUCCESS`.

### Schedule Service

- `Hedera.Client.create_schedule/2` (a scheduled HBAR/token transfer) and `sign_schedule/3`
  (`Hedera.Transaction.schedule_create/1` / `schedule_sign/1`), with `Hedera.ScheduleId` and
  `schedule_id` on the receipt. The scheduled transaction is a `SchedulableTransactionBody` — note
  its data-oneof numbering differs from `TransactionBody` (`cryptoTransfer = 9`). **Validated live**:
  create a transfer pending on a second signer → `sign_schedule` → it executes.

### Token Service — NFTs & token management

- **NFTs** — `token_create` with `token_type: :nft` (NON_FUNGIBLE_UNIQUE); `token_mint` with
  `:metadata` (a list of binaries); mint receipts now expose `serial_numbers` (packed or unpacked).
  NFT transfers via `Hedera.Client.transfer_nft/4` (CryptoTransfer `nftTransfers`).
- **Management** — `freeze_token` / `unfreeze_token`, `grant_kyc` / `revoke_kyc`,
  `wipe_token` (fungible amount or NFT serials), `pause_token` / `unpause_token`. `token_create`
  now accepts `:kyc_key`, `:freeze_key`, `:wipe_key`, `:pause_key`.
- **Validated live** (testnet): create NFT → mint (serials `[1,2]`) → pause/unpause; then
  associate → grantKyc → NFT transfer → freeze/unfreeze → wipe — every step a `SUCCESS` receipt,
  confirming the `tokenFreeze`(31)/`tokenUnfreeze`(32)/`grantKyc`(33)/`revokeKyc`(34)/`tokenWipe`(39)/
  `tokenPause`(46)/`tokenUnpause`(47) field numbers and the `nftTransfers` encoding.

## 0.1.0 — 2026-07-01 — foundation (alpha)

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
