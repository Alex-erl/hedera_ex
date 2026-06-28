defmodule Hedera.Client do
  @moduledoc """
  High-level entry point: holds the operator identity and a target node, builds
  and submits Consensus Service transactions, and reports the node's pre-check
  result.

      client = Hedera.Client.testnet(operator_id, operator_key)
      {:ok, %{precheck_code: 0}} = Hedera.Client.submit_message(client, topic_id, "payload")
  """

  alias Hedera.{AccountId, Grpc, Network, PrivateKey, Proto, TopicId, Transaction, TransactionId}

  @submit_path "/proto.ConsensusService/submitMessage"
  @create_path "/proto.ConsensusService/createTopic"

  @enforce_keys [:operator_id, :operator_key, :node]
  defstruct [:operator_id, :operator_key, :node]

  @type t :: %__MODULE__{
          operator_id: AccountId.t(),
          operator_key: PrivateKey.t(),
          node: Network.node_info()
        }

  @type result :: %{precheck_code: integer(), ok?: boolean(), transaction_id: TransactionId.t()}

  @doc "Build a testnet client for the given operator."
  @spec testnet(AccountId.t(), PrivateKey.t()) :: t()
  def testnet(%AccountId{} = operator_id, %PrivateKey{} = operator_key) do
    %__MODULE__{
      operator_id: operator_id,
      operator_key: operator_key,
      node: Network.default_testnet_node()
    }
  end

  @doc "Submit a message to an HCS topic."
  @spec submit_message(t(), TopicId.t(), binary()) :: {:ok, result()} | {:error, term()}
  def submit_message(%__MODULE__{} = client, %TopicId{} = topic_id, message) do
    Transaction.submit_message(
      operator_id: client.operator_id,
      operator_key: client.operator_key,
      node_account_id: client.node.account_id,
      topic_id: topic_id,
      message: message
    )
    |> execute(client, @submit_path)
  end

  @doc "Create a new HCS topic (open, unless `:memo` given)."
  @spec create_topic(t(), keyword()) :: {:ok, result()} | {:error, term()}
  def create_topic(%__MODULE__{} = client, opts \\ []) do
    Transaction.create_topic(
      [
        operator_id: client.operator_id,
        operator_key: client.operator_key,
        node_account_id: client.node.account_id
      ] ++ opts
    )
    |> execute(client, @create_path)
  end

  defp execute(%{transaction: tx, transaction_id: tx_id}, client, path) do
    case Grpc.unary(client.node.host, client.node.port, path, tx) do
      {:ok, response} ->
        # TransactionResponse { nodeTransactionPrecheckCode = 1 }
        code = Proto.field(Proto.decode(response), 1) || 0
        {:ok, %{precheck_code: code, ok?: code == 0, transaction_id: tx_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
