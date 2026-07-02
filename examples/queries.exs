# Free and paid queries: account balance + account info.
#   OPERATOR_ID=0.0.x OPERATOR_KEY=0x... mix run examples/queries.exs
alias Hedera.{AccountId, Client, PrivateKey}

operator_id = AccountId.parse(System.fetch_env!("OPERATOR_ID"))
operator_key = PrivateKey.from_string_ecdsa(System.fetch_env!("OPERATOR_KEY"))
client = Client.testnet(operator_id, operator_key)

{:ok, %{balance: bal, token_balances: tokens}} = Client.account_balance(client, operator_id)
IO.puts("balance: #{bal} tinybars, #{length(tokens)} token balance(s)  [free query]")

{:ok, info} = Client.account_info(client, operator_id)
IO.puts("info: #{AccountId.to_string(info.account_id)}, balance #{info.balance}, " <>
          "owned_nfts #{info.owned_nfts}, key? #{info.key_present?}  [paid query]")
