# Getting started

`hedera_ex` is a native Elixir SDK for the [Hedera](https://hedera.com) network —
no NIFs, no Java/Go sidecar. It builds and signs Hedera transactions, talks gRPC
to consensus nodes over HTTP/2, and reads the mirror node.

## Install

```elixir
# mix.exs
def deps do
  [{:hedera_ex, "~> 0.7"}]
end
```

## Keys

Hedera accounts use **Ed25519** or **ECDSA secp256k1** keys. Generate or load one:

```elixir
alias Hedera.PrivateKey

key = PrivateKey.generate_ed25519()
# or from a hex string (0x optional):
key = PrivateKey.from_string_ecdsa(System.fetch_env!("OPERATOR_KEY"))

pub = PrivateKey.public_key(key)
```

Private keys are **redacted** in `inspect`/logs (`#Hedera.PrivateKey<ecdsa_secp256k1 [redacted]>`)
— they never leak through a crash dump or `Logger`. See the
[Cryptography](cryptography.md) guide for the signing conventions.

## A client

A client bundles the operator (the account that pays fees) and the node address
book. `testnet/2` uses the built-in testnet nodes with cross-node retry:

```elixir
alias Hedera.{AccountId, Client, PrivateKey}

operator_id  = AccountId.parse("0.0.8260469")
operator_key = PrivateKey.from_string_ecdsa(System.fetch_env!("OPERATOR_KEY"))

client = Client.testnet(operator_id, operator_key)
```

## Your first transaction

Submit a message to a Consensus Service topic and wait for its receipt:

```elixir
alias Hedera.{Client, Receipt, TopicId}

{:ok, result} = Client.submit_message(client, TopicId.parse("0.0.9339331"), "hello hedera")
result.precheck_code   #=> 0  (the node accepted it)
result.ok?             #=> true

{:ok, receipt} = Client.transaction_receipt(client, result.transaction_id)
Receipt.success?(receipt)          #=> true
receipt.topic_sequence_number      #=> e.g. 42
```

Every write returns `{:ok, %{precheck_code: integer, ok?: boolean, transaction_id: TransactionId.t()}}`
or `{:error, reason}`. A `precheck_code` of `0` means the node accepted the
transaction; the **consensus** result (SUCCESS / a failure code) is in the
receipt, fetched separately.

## Where next

- [Transactions](transactions.md) — the full write surface (transfers, tokens,
  files, schedules, contracts, accounts) and multi-signature.
- [Queries](queries.md) — free and paid reads (balances, account info,
  read-only contract calls).
- [Ethereum (EIP-1559)](ethereum.md) — sign and relay Ethereum transactions.
- [Cryptography](cryptography.md) — key types, the Hedera ECDSA convention,
  signing and verification.
