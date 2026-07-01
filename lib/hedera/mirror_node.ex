defmodule Hedera.MirrorNode do
  @moduledoc """
  Thin client for the public Hedera **mirror node** REST API — the read side of
  the network (consensus results, topic messages). Complements the gRPC client,
  which handles writes and receipts.
  """

  alias Hedera.{TopicId, TransactionId}

  @bases %{
    testnet: "https://testnet.mirrornode.hedera.com",
    mainnet: "https://mainnet.mirrornode.hedera.com",
    previewnet: "https://previewnet.mirrornode.hedera.com"
  }

  @doc "Fetch a single topic message by sequence number. Returns the decoded JSON map."
  @spec topic_message(TopicId.t(), non_neg_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def topic_message(%TopicId{} = topic_id, sequence_number, opts \\ []) do
    get("/api/v1/topics/#{TopicId.to_string(topic_id)}/messages/#{sequence_number}", opts)
  end

  @doc "Look up a transaction by id (`shard.realm.num@secs.nanos`)."
  @spec transaction(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def transaction(transaction_id, opts) when is_binary(transaction_id) do
    get("/api/v1/transactions/#{normalize_tx_id(transaction_id)}", opts)
  end

  @doc """
  Read a smart-contract call's result — the contract's **return value** (from the
  transaction record) that isn't in the receipt. Accepts a `TransactionId` or its
  string form. The returned JSON map includes `"call_result"` (hex-encoded return
  bytes), `"gas_used"`, `"error_message"` and more. Subject to mirror-node
  ingestion lag after consensus.
  """
  @spec contract_result(TransactionId.t() | binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def contract_result(tx_id, opts \\ [])

  def contract_result(%TransactionId{} = tx_id, opts),
    do: contract_result(TransactionId.to_string(tx_id), opts)

  def contract_result(tx_id, opts) when is_binary(tx_id) do
    get("/api/v1/contracts/results/#{normalize_tx_id(tx_id)}", opts)
  end

  # --- internals --------------------------------------------------------------

  defp get(path, opts) do
    base = Map.fetch!(@bases, Keyword.get(opts, :network, :testnet))
    url = String.to_charlist(base <> path)
    http_opts = [ssl: ssl_opts(), timeout: Keyword.get(opts, :timeout, 15_000)]

    case :httpc.request(:get, {url, [{~c"accept", ~c"application/json"}]}, http_opts,
           body_format: :binary
         ) do
      {:ok, {{_v, 200, _r}, _headers, body}} -> Jason.decode(body)
      {:ok, {{_v, status, _r}, _headers, _body}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # mirror node encodes "shard.realm.num@secs.nanos" as "shard.realm.num-secs-nanos"
  defp normalize_tx_id(id) do
    case String.split(id, "@") do
      [account, valid_start] -> account <> "-" <> String.replace(valid_start, ".", "-")
      _ -> id
    end
  end

  defp ssl_opts do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 4,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]
  end
end
