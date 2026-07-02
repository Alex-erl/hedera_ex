# Fungible token lifecycle: create -> mint -> burn.
#   OPERATOR_ID=0.0.x OPERATOR_KEY=0x... mix run examples/token_lifecycle.exs
alias Hedera.{AccountId, Client, PrivateKey, Receipt}

operator_id = AccountId.parse(System.fetch_env!("OPERATOR_ID"))
operator_key = PrivateKey.from_string_ecdsa(System.fetch_env!("OPERATOR_KEY"))
client = Client.testnet(operator_id, operator_key)
pub = PrivateKey.public_key(operator_key)

{:ok, created} =
  Client.create_token(client,
    name: "hedera_ex Demo",
    symbol: "HEX",
    decimals: 2,
    initial_supply: 1_000,
    treasury: operator_id,
    admin_key: pub,
    supply_key: pub
  )

{:ok, receipt} = Client.transaction_receipt(client, created.transaction_id)
token = receipt.token_id
IO.puts("created token #{Hedera.TokenId.to_string(token)}")

{:ok, minted} = Client.mint_token(client, token, 500)
{:ok, r1} = Client.transaction_receipt(client, minted.transaction_id)
IO.puts("after mint: total supply #{r1.new_total_supply}")

{:ok, burned} = Client.burn_token(client, token, 200)
{:ok, r2} = Client.transaction_receipt(client, burned.transaction_id)
IO.puts("after burn: total supply #{r2.new_total_supply} (#{if Receipt.success?(r2), do: "SUCCESS", else: r2.status})")
