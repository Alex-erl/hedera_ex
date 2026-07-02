# Submit a Consensus Service message and read its receipt.
#   OPERATOR_ID=0.0.x OPERATOR_KEY=0x... mix run examples/hcs.exs
alias Hedera.{AccountId, Client, PrivateKey, Receipt, TopicId}

operator_id = AccountId.parse(System.fetch_env!("OPERATOR_ID"))
operator_key = PrivateKey.from_string_ecdsa(System.fetch_env!("OPERATOR_KEY"))
client = Client.testnet(operator_id, operator_key)

# create a topic, then submit to it
{:ok, created} = Client.create_topic(client, memo: "hedera_ex demo")
{:ok, receipt} = Client.transaction_receipt(client, created.transaction_id)
topic = receipt.topic_id
IO.puts("created topic #{TopicId.to_string(topic)}")

{:ok, sent} = Client.submit_message(client, topic, "hello from hedera_ex")
IO.puts("submit precheck: #{sent.precheck_code}")

{:ok, r} = Client.transaction_receipt(client, sent.transaction_id)
IO.puts("consensus: #{if Receipt.success?(r), do: "SUCCESS", else: r.status}, seq #{r.topic_sequence_number}")
