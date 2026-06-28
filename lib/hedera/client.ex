defmodule Hedera.Client do
  @moduledoc """
  High-level entry point: holds the operator identity and the network's node
  address book, builds and submits Consensus Service transactions, retries
  across nodes on transient failures, and fetches receipts.

      client = Hedera.Client.testnet(operator_id, operator_key)
      {:ok, %{precheck_code: 0}} = Hedera.Client.submit_message(client, topic_id, "payload")
  """

  alias Hedera.{
    AccountId,
    Grpc,
    Network,
    PrivateKey,
    Proto,
    Receipt,
    TopicId,
    Transaction,
    TransactionId
  }

  @submit_path "/proto.ConsensusService/submitMessage"
  @create_path "/proto.ConsensusService/createTopic"
  @transfer_path "/proto.CryptoService/cryptoTransfer"
  @receipt_path "/proto.CryptoService/getTransactionReceipts"

  @f_receipt_query 14
  @f_receipt_response 14

  # ResponseCodeEnum.BUSY — worth retrying on another node.
  @busy 11

  @enforce_keys [:operator_id, :operator_key, :nodes]
  defstruct [:operator_id, :operator_key, :nodes]

  @type t :: %__MODULE__{
          operator_id: AccountId.t(),
          operator_key: PrivateKey.t(),
          nodes: [Network.node_info()]
        }

  @type result :: %{precheck_code: integer(), ok?: boolean(), transaction_id: TransactionId.t()}

  @doc "Build a testnet client (with the full testnet node address book)."
  @spec testnet(AccountId.t(), PrivateKey.t()) :: t()
  def testnet(%AccountId{} = operator_id, %PrivateKey{} = operator_key) do
    %__MODULE__{
      operator_id: operator_id,
      operator_key: operator_key,
      nodes: Network.testnet_nodes()
    }
  end

  @doc "Submit a message to an HCS topic (retries across nodes on transient errors)."
  @spec submit_message(t(), TopicId.t(), binary()) :: {:ok, result()} | {:error, term()}
  def submit_message(%__MODULE__{} = client, %TopicId{} = topic_id, message) do
    execute(client, @submit_path, fn node ->
      Transaction.submit_message(
        operator_id: client.operator_id,
        operator_key: client.operator_key,
        node_account_id: node.account_id,
        topic_id: topic_id,
        message: message
      )
    end)
  end

  @doc "Create a new HCS topic (open, unless `:memo` given)."
  @spec create_topic(t(), keyword()) :: {:ok, result()} | {:error, term()}
  def create_topic(%__MODULE__{} = client, opts \\ []) do
    execute(client, @create_path, fn node ->
      Transaction.create_topic(
        [
          operator_id: client.operator_id,
          operator_key: client.operator_key,
          node_account_id: node.account_id
        ] ++ opts
      )
    end)
  end

  @doc """
  Transfer HBAR between accounts (retries across nodes on transient errors).

  `transfers` is a list of `{%AccountId{}, amount_in_tinybars}` pairs; debits are
  negative, credits positive, and they must net to zero.

      Hedera.Client.transfer_hbar(client, [{from, -1}, {to, 1}])
  """
  @spec transfer_hbar(t(), [{AccountId.t(), integer()}], keyword()) ::
          {:ok, result()} | {:error, term()}
  def transfer_hbar(%__MODULE__{} = client, transfers, opts \\ []) when is_list(transfers) do
    execute(client, @transfer_path, fn node ->
      Transaction.crypto_transfer(
        [
          operator_id: client.operator_id,
          operator_key: client.operator_key,
          node_account_id: node.account_id,
          transfers: transfers
        ] ++ opts
      )
    end)
  end

  @doc "Fetch a transaction's consensus receipt, polling until final (free query)."
  @spec transaction_receipt(t(), TransactionId.t(), keyword()) ::
          {:ok, Receipt.t()} | {:error, term()}
  def transaction_receipt(%__MODULE__{nodes: [node | _]}, %TransactionId{} = tx_id, opts \\ []) do
    attempts = Keyword.get(opts, :attempts, 8)
    delay = Keyword.get(opts, :delay_ms, 2_000)
    poll_receipt(node, tx_id, attempts, delay)
  end

  # --- execution with cross-node retry ----------------------------------------

  defp execute(%__MODULE__{nodes: nodes}, path, build_fun) do
    attempt(nodes, path, build_fun, {:error, :no_nodes})
  end

  defp attempt([], _path, _build_fun, last_error), do: last_error

  defp attempt([node | rest], path, build_fun, _last) do
    %{transaction: tx, transaction_id: tx_id} = build_fun.(node)

    case Grpc.unary(node.host, node.port, path, tx) do
      {:ok, response} ->
        code = Proto.field(Proto.decode(response), 1) || 0
        result = {:ok, %{precheck_code: code, ok?: code == 0, transaction_id: tx_id}}
        # success or a permanent rejection → stop; transient (BUSY) → next node
        if code == 0 or code != @busy, do: result, else: attempt(rest, path, build_fun, result)

      {:error, reason} ->
        attempt(rest, path, build_fun, {:error, reason})
    end
  end

  # --- receipt polling --------------------------------------------------------

  defp poll_receipt(_node, _tx_id, 0, _delay), do: {:error, :receipt_not_available}

  defp poll_receipt(node, tx_id, attempts, delay) do
    case query_receipt(node, tx_id) do
      {:ok, receipt} ->
        if Receipt.final?(receipt) do
          {:ok, receipt}
        else
          Process.sleep(delay)
          poll_receipt(node, tx_id, attempts - 1, delay)
        end

      {:error, _transient} ->
        Process.sleep(delay)
        poll_receipt(node, tx_id, attempts - 1, delay)
    end
  end

  defp query_receipt(node, tx_id) do
    receipt_query =
      Proto.bytes_field(1, <<>>) <> Proto.bytes_field(2, TransactionId.to_proto(tx_id))

    query = Proto.bytes_field(@f_receipt_query, receipt_query)

    with {:ok, response} <- Grpc.unary(node.host, node.port, @receipt_path, query) do
      inner = Proto.decode(Proto.field(Proto.decode(response), @f_receipt_response) || <<>>)

      case Proto.field(inner, 2) do
        nil ->
          precheck = Proto.field(Proto.decode(Proto.field(inner, 1) || <<>>), 1) || 0
          {:error, {:no_receipt, precheck}}

        receipt_bytes ->
          {:ok, Receipt.parse(receipt_bytes)}
      end
    end
  end
end
