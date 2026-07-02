# Queries

Hedera has two kinds of reads: **free** queries (the node answers for nothing)
and **paid** queries (the request must carry a signed payment covering the query
fee). `hedera_ex` handles the payment for you.

## Free — account balance

```elixir
{:ok, %{balance: tinybars, token_balances: tokens}} =
  Client.account_balance(client, AccountId.parse("0.0.8260469"))
```

`token_balances` is a list of `%{token_id:, balance:, decimals:}`.

## Paid — account info

The `QueryHeader.payment` is a signed `CryptoTransfer` paying the node; the fee is
`:query_payment` tinybars (default `100_000`):

```elixir
{:ok, info} = Client.account_info(client, account, query_payment: 100_000)

info.account_id             #=> %AccountId{}
info.balance                #=> tinybars
info.memo                   #=> string
info.deleted                #=> boolean
info.owned_nfts             #=> integer
info.receiver_sig_required  #=> boolean
info.key_present?           #=> boolean
```

## Paid — read-only contract call (`contractCallLocal`)

Execute a contract call on a node and read its return value **without** a
consensus transaction (no state change, no consensus fee — just the query fee):

```elixir
{:ok, %{result: bytes, gas_used: gas, error_message: err}} =
  Client.call_contract_local(client, contract,
    gas: 50_000,
    function_parameters: abi_encoded_call
  )
```

`result` is the raw ABI-encoded return value; decode it with your ABI helper.
`error_message` is `nil` on success.

## Consensus results

For a transaction's outcome, use `Client.transaction_receipt/3` (a free query that
polls until final) — see [Transactions](transactions.md). For a contract call's
return value **after** a consensus `call_contract/3`, read the transaction record
via the mirror node:

```elixir
{:ok, record} = Hedera.MirrorNode.contract_result(tx_id)
record["call_result"]   # hex-encoded return bytes (subject to mirror-node lag)
```

> Note: the free/paid query functions currently target the first node in the
> address book (no cross-node retry, unlike the write path). Retry at the call
> site if a specific node is unavailable.
