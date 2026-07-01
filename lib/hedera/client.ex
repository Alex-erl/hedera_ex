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
    ContractId,
    FileId,
    Grpc,
    Network,
    Pb,
    PrivateKey,
    Receipt,
    ScheduleId,
    TokenId,
    TopicId,
    Transaction,
    TransactionId
  }

  @submit_path "/proto.ConsensusService/submitMessage"
  @create_path "/proto.ConsensusService/createTopic"
  @transfer_path "/proto.CryptoService/cryptoTransfer"
  @token_create_path "/proto.TokenService/createToken"
  @token_mint_path "/proto.TokenService/mintToken"
  @token_burn_path "/proto.TokenService/burnToken"
  @token_associate_path "/proto.TokenService/associateTokens"
  @token_freeze_path "/proto.TokenService/freezeTokenAccount"
  @token_unfreeze_path "/proto.TokenService/unfreezeTokenAccount"
  @token_grant_kyc_path "/proto.TokenService/grantKycToTokenAccount"
  @token_revoke_kyc_path "/proto.TokenService/revokeKycFromTokenAccount"
  @token_wipe_path "/proto.TokenService/wipeTokenAccount"
  @token_pause_path "/proto.TokenService/pauseToken"
  @token_unpause_path "/proto.TokenService/unpauseToken"
  @file_create_path "/proto.FileService/createFile"
  @file_append_path "/proto.FileService/appendContent"
  @file_update_path "/proto.FileService/updateFile"
  @file_delete_path "/proto.FileService/deleteFile"
  @schedule_create_path "/proto.ScheduleService/createSchedule"
  @schedule_sign_path "/proto.ScheduleService/signSchedule"
  @contract_create_path "/proto.SmartContractService/createContract"
  @contract_call_path "/proto.SmartContractService/contractCallMethod"
  @receipt_path "/proto.CryptoService/getTransactionReceipts"

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

  @doc """
  Create a new HTS token. See `Hedera.Transaction.token_create/1` for opts
  (`:treasury` is required). The new token's id is in the receipt's `token_id`.
  """
  @spec create_token(t(), keyword()) :: {:ok, result()} | {:error, term()}
  def create_token(%__MODULE__{} = client, opts \\ []) do
    execute(client, @token_create_path, fn node ->
      Transaction.token_create(with_operator(client, node, opts))
    end)
  end

  @doc "Mint `amount` of (or `:metadata` for) a token. Needs the supply key."
  @spec mint_token(t(), TokenId.t(), non_neg_integer(), keyword()) ::
          {:ok, result()} | {:error, term()}
  def mint_token(%__MODULE__{} = client, %TokenId{} = token, amount, opts \\ []) do
    execute(client, @token_mint_path, fn node ->
      Transaction.token_mint(with_operator(client, node, [token: token, amount: amount] ++ opts))
    end)
  end

  @doc "Burn `amount` of a token from the treasury. Needs the supply key."
  @spec burn_token(t(), TokenId.t(), non_neg_integer(), keyword()) ::
          {:ok, result()} | {:error, term()}
  def burn_token(%__MODULE__{} = client, %TokenId{} = token, amount, opts \\ []) do
    execute(client, @token_burn_path, fn node ->
      Transaction.token_burn(with_operator(client, node, [token: token, amount: amount] ++ opts))
    end)
  end

  @doc """
  Associate `tokens` with `account`. The account must sign; when it is not the
  operator, pass its key via `signers: [account_key]` in `opts`.
  """
  @spec associate_token(t(), AccountId.t(), [TokenId.t()], keyword()) ::
          {:ok, result()} | {:error, term()}
  def associate_token(%__MODULE__{} = client, %AccountId{} = account, tokens, opts \\ []) do
    execute(client, @token_associate_path, fn node ->
      Transaction.token_associate(
        with_operator(client, node, [account: account, tokens: tokens] ++ opts)
      )
    end)
  end

  @doc """
  Transfer an HTS token between accounts. `moves` is a list of
  `{%AccountId{}, amount}` pairs that must net to zero (debits negative).
  """
  @spec transfer_token(t(), TokenId.t(), [{AccountId.t(), integer()}], keyword()) ::
          {:ok, result()} | {:error, term()}
  def transfer_token(%__MODULE__{} = client, %TokenId{} = token, moves, opts \\ [])
      when is_list(moves) do
    execute(client, @transfer_path, fn node ->
      Transaction.crypto_transfer(
        with_operator(client, node, [token_transfers: [{token, moves}]] ++ opts)
      )
    end)
  end

  @doc """
  Transfer NFTs of `token`. `moves` is a list of `{sender, receiver, serial}`
  tuples (`AccountId`s + integer serial). Needs sender authorization.
  """
  @spec transfer_nft(t(), TokenId.t(), [{AccountId.t(), AccountId.t(), integer()}], keyword()) ::
          {:ok, result()} | {:error, term()}
  def transfer_nft(%__MODULE__{} = client, %TokenId{} = token, moves, opts \\ [])
      when is_list(moves) do
    execute(client, @transfer_path, fn node ->
      Transaction.crypto_transfer(
        with_operator(client, node, [nft_transfers: [{token, moves}]] ++ opts)
      )
    end)
  end

  @doc "Freeze `token` for `account` (needs the freeze key)."
  @spec freeze_token(t(), TokenId.t(), AccountId.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def freeze_token(client, token, account, opts \\ []),
    do: token_account_op(client, @token_freeze_path, &Transaction.token_freeze/1, token, account, opts)

  @doc "Unfreeze `token` for `account` (needs the freeze key)."
  @spec unfreeze_token(t(), TokenId.t(), AccountId.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def unfreeze_token(client, token, account, opts \\ []),
    do: token_account_op(client, @token_unfreeze_path, &Transaction.token_unfreeze/1, token, account, opts)

  @doc "Grant KYC of `token` to `account` (needs the KYC key)."
  @spec grant_kyc(t(), TokenId.t(), AccountId.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def grant_kyc(client, token, account, opts \\ []),
    do: token_account_op(client, @token_grant_kyc_path, &Transaction.token_grant_kyc/1, token, account, opts)

  @doc "Revoke KYC of `token` from `account` (needs the KYC key)."
  @spec revoke_kyc(t(), TokenId.t(), AccountId.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def revoke_kyc(client, token, account, opts \\ []),
    do: token_account_op(client, @token_revoke_kyc_path, &Transaction.token_revoke_kyc/1, token, account, opts)

  @doc """
  Wipe a token balance from `account` (needs the wipe key). Pass `amount:` for a
  fungible token or `serials:` (a list) for NFTs in `opts`.
  """
  @spec wipe_token(t(), TokenId.t(), AccountId.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def wipe_token(%__MODULE__{} = client, %TokenId{} = token, %AccountId{} = account, opts \\ []) do
    execute(client, @token_wipe_path, fn node ->
      Transaction.token_wipe(with_operator(client, node, [token: token, account: account] ++ opts))
    end)
  end

  @doc "Pause `token` (needs the pause key)."
  @spec pause_token(t(), TokenId.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def pause_token(%__MODULE__{} = client, %TokenId{} = token, opts \\ []) do
    execute(client, @token_pause_path, fn node ->
      Transaction.token_pause(with_operator(client, node, [token: token] ++ opts))
    end)
  end

  @doc "Unpause `token` (needs the pause key)."
  @spec unpause_token(t(), TokenId.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def unpause_token(%__MODULE__{} = client, %TokenId{} = token, opts \\ []) do
    execute(client, @token_unpause_path, fn node ->
      Transaction.token_unpause(with_operator(client, node, [token: token] ++ opts))
    end)
  end

  ## File Service

  @doc "Create a file. See `Hedera.Transaction.file_create/1` for opts. New file id is in the receipt."
  @spec create_file(t(), keyword()) :: {:ok, result()} | {:error, term()}
  def create_file(%__MODULE__{} = client, opts \\ []) do
    execute(client, @file_create_path, fn node ->
      Transaction.file_create(with_operator(client, node, opts))
    end)
  end

  @doc "Append `contents` to `file` (needs the file's key)."
  @spec append_file(t(), FileId.t(), binary(), keyword()) :: {:ok, result()} | {:error, term()}
  def append_file(%__MODULE__{} = client, %FileId{} = file, contents, opts \\ []) do
    execute(client, @file_append_path, fn node ->
      Transaction.file_append(with_operator(client, node, [file: file, contents: contents] ++ opts))
    end)
  end

  @doc "Update `file` (opts: `:contents`, `:keys`, `:expiration_seconds`). Needs the file's key."
  @spec update_file(t(), FileId.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def update_file(%__MODULE__{} = client, %FileId{} = file, opts \\ []) do
    execute(client, @file_update_path, fn node ->
      Transaction.file_update(with_operator(client, node, [file: file] ++ opts))
    end)
  end

  @doc "Delete `file` (needs the file's key)."
  @spec delete_file(t(), FileId.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def delete_file(%__MODULE__{} = client, %FileId{} = file, opts \\ []) do
    execute(client, @file_delete_path, fn node ->
      Transaction.file_delete(with_operator(client, node, [file: file] ++ opts))
    end)
  end

  ## Schedule Service

  @doc "Create a scheduled transfer. See `Hedera.Transaction.schedule_create/1`. Schedule id is in the receipt."
  @spec create_schedule(t(), keyword()) :: {:ok, result()} | {:error, term()}
  def create_schedule(%__MODULE__{} = client, opts \\ []) do
    execute(client, @schedule_create_path, fn node ->
      Transaction.schedule_create(with_operator(client, node, opts))
    end)
  end

  @doc "Add the operator's (and any `:signers`') signature to a pending schedule."
  @spec sign_schedule(t(), ScheduleId.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def sign_schedule(%__MODULE__{} = client, %ScheduleId{} = schedule_id, opts \\ []) do
    execute(client, @schedule_sign_path, fn node ->
      Transaction.schedule_sign(with_operator(client, node, [schedule_id: schedule_id] ++ opts))
    end)
  end

  ## Smart Contract Service

  @doc """
  Deploy a smart contract. See `Hedera.Transaction.contract_create/1` for opts
  (`:bytecode` or `:file`, plus `:gas` etc.). New contract id is in the receipt.
  """
  @spec create_contract(t(), keyword()) :: {:ok, result()} | {:error, term()}
  def create_contract(%__MODULE__{} = client, opts \\ []) do
    execute(client, @contract_create_path, fn node ->
      Transaction.contract_create(with_operator(client, node, opts))
    end)
  end

  @doc """
  Call a contract method. Opts: `:gas`, `:amount`, `:function_parameters`
  (ABI-encoded). The return value is in the record, not the receipt.
  """
  @spec call_contract(t(), ContractId.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def call_contract(%__MODULE__{} = client, %ContractId{} = contract, opts \\ []) do
    execute(client, @contract_call_path, fn node ->
      Transaction.contract_call(with_operator(client, node, [contract: contract] ++ opts))
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

  # Prepend the standard operator/node options to a per-call opts list.
  defp with_operator(%__MODULE__{} = client, node, opts) do
    [
      operator_id: client.operator_id,
      operator_key: client.operator_key,
      node_account_id: node.account_id
    ] ++ opts
  end

  # Shared shape for the {token, account} token-management operations.
  defp token_account_op(client, path, builder, %TokenId{} = token, %AccountId{} = account, opts) do
    execute(client, path, fn node ->
      builder.(with_operator(client, node, [token: token, account: account] ++ opts))
    end)
  end

  defp execute(%__MODULE__{nodes: nodes}, path, build_fun) do
    attempt(nodes, path, build_fun, {:error, :no_nodes})
  end

  defp attempt([], _path, _build_fun, last_error), do: last_error

  defp attempt([node | rest], path, build_fun, _last) do
    %{transaction: tx, transaction_id: tx_id} = build_fun.(node)

    case Grpc.unary(node.host, node.port, path, tx) do
      {:ok, response} ->
        code = Pb.TransactionResponse.decode(response).nodeTransactionPrecheckCode
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
    # a free receipt query: an empty payment with ANSWER_ONLY
    query = %Pb.Query{
      query:
        {:transactionGetReceipt,
         %Pb.TransactionGetReceiptQuery{
           header: %Pb.QueryHeader{payment: %Pb.Transaction{}, responseType: :ANSWER_ONLY},
           transactionID: pb_txid(tx_id)
         }}
    }

    with {:ok, response} <- Grpc.unary(node.host, node.port, @receipt_path, encode(Pb.Query, query)) do
      case Pb.Response.decode(response).response do
        {:transactionGetReceipt, %Pb.TransactionGetReceiptResponse{receipt: nil, header: header}} ->
          {:error, {:no_receipt, header && header.nodeTransactionPrecheckCode}}

        {:transactionGetReceipt, %Pb.TransactionGetReceiptResponse{receipt: receipt}} ->
          {:ok, Receipt.from_pb(receipt)}

        _ ->
          {:error, :unexpected_receipt_response}
      end
    end
  end

  defp pb_txid(%TransactionId{account_id: a, valid_start: ts}) do
    %Pb.TransactionID{
      transactionValidStart: %Pb.Timestamp{seconds: ts.seconds, nanos: ts.nanos},
      accountID: %Pb.AccountID{shardNum: a.shard, realmNum: a.realm, accountNum: a.num}
    }
  end

  defp encode(mod, struct), do: struct |> mod.encode() |> IO.iodata_to_binary()
end
