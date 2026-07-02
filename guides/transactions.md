# Transactions

Every write goes through the same pipeline: `Hedera.Transaction` builds a
`TransactionBody`, signs it (the operator always signs; extra keys via
`:signers`), and wraps it as a `SignedTransaction`. `Hedera.Client` sends it with
cross-node retry. All field numbers are the canonical Hedera HAPI values.

## The result shape

```elixir
{:ok, %{precheck_code: 0, ok?: true, transaction_id: tx_id}} =
  Client.transfer_hbar(client, [{from, -1}, {to, 1}])
```

`precheck_code == 0` means the node accepted it. For the consensus outcome, fetch
the receipt:

```elixir
{:ok, receipt} = Client.transaction_receipt(client, tx_id)
Hedera.Receipt.success?(receipt)
```

A created entity's id is on the receipt: `receipt.account_id`, `receipt.token_id`,
`receipt.file_id`, `receipt.schedule_id`, `receipt.contract_id`,
`receipt.topic_id`, plus `new_total_supply` and `serial_numbers`.

## Multi-signature

Pass extra required signers with `:signers` — e.g. associating a token to an
account the operator doesn't control:

```elixir
Client.associate_token(client, account, [token], signers: [account_key])
```

The operator (fee payer) always signs; each distinct key adds one signature.

## The write surface

### Crypto Service — HBAR & accounts

```elixir
# balanced HBAR transfer (must net to zero; amounts are tinybars)
Client.transfer_hbar(client, [{operator_id, -100}, {recipient, 100}])

# account lifecycle — the new id comes back in receipt.account_id
{:ok, r}      = Client.create_account(client, key: PublicKey, initial_balance: 0)
{:ok, receipt} = Client.transaction_receipt(client, r.transaction_id)
new_account   = receipt.account_id

Client.update_account(client, new_account, account_memo: "renamed")
Client.delete_account(client, new_account, transfer_account: operator_id, signers: [new_key])
```

### Token Service (HTS)

```elixir
Client.create_token(client, name: "My Token", symbol: "MTK", initial_supply: 1000,
  treasury: operator_id, admin_key: pub, supply_key: pub, fee_schedule_key: pub)

Client.mint_token(client, token, 500)
Client.burn_token(client, token, 100)
Client.associate_token(client, account, [token], signers: [account_key])
Client.transfer_token(client, token, [{operator_id, -10}, {recipient, 10}])

# NFTs
Client.create_token(client, token_type: :nft, supply_type: :finite, max_supply: 100,
  treasury: operator_id, supply_key: pub)
Client.mint_token(client, nft, 0, metadata: ["ipfs://…"])
Client.transfer_nft(client, nft, [{operator_id, recipient, 1}])

# management: freeze/unfreeze, grant/revoke KYC, wipe, pause/unpause, update, delete,
# dissociate, and custom fee schedules
Client.update_token(client, token, name: "Renamed", admin_key: pub)
Client.update_token_fee_schedule(client, token, [
  %{type: :fixed, amount: 5, collector: operator_id},
  %{type: :fractional, numerator: 1, denominator: 100, minimum: 1, maximum: 50, collector: operator_id}
])
```

### File, Schedule, Smart Contract Services

```elixir
{:ok, r} = Client.create_file(client, contents: "hello", keys: [pub])
Client.append_file(client, file, "more")

Client.create_schedule(client, ...)   # scheduled tx + multi-sig collection
Client.sign_schedule(client, schedule_id)

Client.create_contract(client, bytecode: evm_init, gas: 100_000)
Client.call_contract(client, contract, function_parameters: abi_encoded)
```

For read-only contract calls and account queries, see [Queries](queries.md); for
signing Ethereum transactions, see [Ethereum](ethereum.md).

## Building without sending

`Hedera.Transaction.*` builders return `%{transaction: bytes, transaction_id: id}`
if you want to inspect or route the signed bytes yourself. Each builder documents
its required and optional opts.
