defmodule Hedera.Transaction do
  @moduledoc """
  Builds and signs Hedera transactions for the Consensus, Crypto and Token
  Services.

  The flow follows the Hedera HAPI: encode a `TransactionBody`, sign its exact
  bytes with the operator key (and any additional `:signers`), wrap them in a
  `SignedTransaction` (bodyBytes + signature map), and finally a `Transaction`
  (signedTransactionBytes). The signature is computed over the precise
  `bodyBytes` that are transmitted.

  Protobuf field numbers are taken from the canonical Hedera protobufs and are
  validated end-to-end against a live node by the gRPC layer.
  """

  alias Hedera.{
    AccountId,
    Duration,
    FileId,
    Proto,
    PrivateKey,
    PublicKey,
    ScheduleId,
    Timestamp,
    TokenId,
    TopicId,
    TransactionId
  }

  # default max fee: 2 ℏ in tinybars (token create needs a higher ceiling)
  @default_max_fee 200_000_000
  @default_token_create_fee 4_000_000_000
  @default_valid_seconds 120
  # token auto-renew default: ~90 days (within Hedera's accepted range)
  @default_auto_renew_seconds 7_776_000

  # TransactionBody field numbers
  @f_transaction_id 1
  @f_node_account 2
  @f_fee 3
  @f_valid_duration 4
  @f_memo 6
  # data oneof
  @f_file_append 16
  @f_file_create 17
  @f_file_delete 18
  @f_file_update 19
  @f_crypto_transfer 14
  @f_consensus_create_topic 24
  @f_consensus_submit_message 27
  @f_schedule_create 42
  @f_schedule_sign 44
  # SchedulableTransactionBody data oneof (distinct numbering from TransactionBody)
  @f_schedulable_crypto_transfer 9
  @f_token_creation 29
  @f_token_freeze 31
  @f_token_unfreeze 32
  @f_token_grant_kyc 33
  @f_token_revoke_kyc 34
  @f_token_mint 37
  @f_token_burn 38
  @f_token_wipe 39
  @f_token_associate 40
  @f_token_pause 46
  @f_token_unpause 47

  @type build_result :: %{transaction: binary(), transaction_id: TransactionId.t()}

  @doc """
  Build + sign a `consensusSubmitMessage` transaction.

  Required opts: `:operator_id`, `:operator_key`, `:node_account_id`, `:topic_id`,
  `:message`. Optional: `:max_fee`, `:memo`.
  """
  @spec submit_message(keyword()) :: build_result()
  def submit_message(opts) do
    topic_id = fetch!(opts, :topic_id)
    message = fetch!(opts, :message)

    inner =
      Proto.bytes_field(1, TopicId.to_proto(topic_id)) <> Proto.bytes_field(2, message)

    build(opts, @f_consensus_submit_message, inner)
  end

  @doc """
  Build + sign a `consensusCreateTopic` transaction. By default the topic is
  open (no admin/submit key). Optional: `:memo`, `:max_fee`.
  """
  @spec create_topic(keyword()) :: build_result()
  def create_topic(opts) do
    inner = Proto.maybe_bytes_field(1, opts[:memo])
    build(opts, @f_consensus_create_topic, inner)
  end

  @doc """
  Build + sign a `cryptoTransfer` of HBAR and/or HTS tokens.

  Opts (standard operator/node options plus):

    * `:transfers` — HBAR moves, a list of `{%AccountId{}, tinybars}` pairs.
    * `:token_transfers` — token moves, a list of
      `{%TokenId{}, [{%AccountId{}, amount}]}` pairs.

  Debits are negative, credits positive, and each currency (HBAR, and every
  token independently) MUST net to zero. Amounts are encoded as protobuf
  `sint64` (ZigZag), matching `AccountAmount`. Optional: `:memo`, `:max_fee`.
  """
  @spec crypto_transfer(keyword()) :: build_result()
  def crypto_transfer(opts) do
    build(opts, @f_crypto_transfer, crypto_transfer_body(opts))
  end

  # The bare CryptoTransferTransactionBody bytes (no TransactionBody wrapper);
  # reused when scheduling a transfer.
  defp crypto_transfer_body(opts) do
    hbar = Keyword.get(opts, :transfers, [])
    token_transfers = Keyword.get(opts, :token_transfers, [])
    nft_transfers = Keyword.get(opts, :nft_transfers, [])

    # CryptoTransferTransactionBody { TransferList transfers = 1 } — omitted when
    # there are no HBAR moves (proto3 leaves the empty message unset).
    hbar_field =
      case hbar do
        [] -> <<>>
        list -> Proto.bytes_field(1, account_amounts(list, 1))
      end

    # repeated TokenTransferList tokenTransfers = 2, grouping fungible moves
    # (transfers = 2) and/or NFT moves (nftTransfers = 3) per token.
    token_fields =
      Enum.map_join(token_transfers, "", fn {%TokenId{} = token, moves} ->
        ttl = Proto.bytes_field(1, TokenId.to_proto(token)) <> account_amounts(moves, 2)
        Proto.bytes_field(2, ttl)
      end)

    nft_fields =
      Enum.map_join(nft_transfers, "", fn {%TokenId{} = token, moves} ->
        ttl = Proto.bytes_field(1, TokenId.to_proto(token)) <> nft_transfer_list(moves)
        Proto.bytes_field(2, ttl)
      end)

    hbar_field <> token_fields <> nft_fields
  end

  @doc """
  Build + sign a `tokenCreation`. Required: `:treasury` (an `AccountId`).
  Common opts: `:name`, `:symbol`, `:decimals`, `:initial_supply`, `:token_type`
  (`:fungible` | `:nft`), `:supply_type` (`:infinite` | `:finite`), `:max_supply`,
  `:token_memo`, `:auto_renew_account`, `:auto_renew_period`. Key opts (all
  `PublicKey`s, all optional): `:admin_key`, `:supply_key` (mint/burn),
  `:kyc_key`, `:freeze_key`, `:wipe_key`, `:pause_key` — a management operation
  only works if the matching key was set at creation.

  The treasury account (and the admin key, if set) must sign — pass extra keys
  via `:signers` when they differ from the operator.
  """
  @spec token_create(keyword()) :: build_result()
  def token_create(opts) do
    treasury = fetch!(opts, :treasury)
    auto_renew = Keyword.get(opts, :auto_renew_account, treasury)
    renew_period = Keyword.get(opts, :auto_renew_period, @default_auto_renew_seconds)

    inner =
      Proto.bytes_field(1, Keyword.get(opts, :name, "")) <>
        Proto.bytes_field(2, Keyword.get(opts, :symbol, "")) <>
        maybe_varint(3, Keyword.get(opts, :decimals, 0)) <>
        maybe_varint(4, Keyword.get(opts, :initial_supply, 0)) <>
        Proto.bytes_field(5, AccountId.to_proto(treasury)) <>
        maybe_key(6, opts[:admin_key]) <>
        maybe_key(7, opts[:kyc_key]) <>
        maybe_key(8, opts[:freeze_key]) <>
        maybe_key(9, opts[:wipe_key]) <>
        maybe_key(10, opts[:supply_key]) <>
        maybe_varint(11, bool_int(Keyword.get(opts, :freeze_default, false))) <>
        Proto.bytes_field(14, AccountId.to_proto(auto_renew)) <>
        Proto.bytes_field(15, Duration.to_proto(%Duration{seconds: renew_period})) <>
        maybe_string(16, opts[:token_memo]) <>
        maybe_varint(17, token_type(Keyword.get(opts, :token_type, :fungible))) <>
        maybe_varint(18, supply_type(Keyword.get(opts, :supply_type, :infinite))) <>
        maybe_varint(19, Keyword.get(opts, :max_supply, 0)) <>
        maybe_key(22, opts[:pause_key])

    fee = Keyword.get(opts, :max_fee, @default_token_create_fee)
    build(Keyword.put(opts, :max_fee, fee), @f_token_creation, inner)
  end

  @doc """
  Build + sign a `tokenMint`. Required: `:token` (a `TokenId`). For fungible
  tokens pass `:amount` (smallest unit); for NFTs pass `:metadata` (a list of
  binaries). Requires the token's supply key to sign.
  """
  @spec token_mint(keyword()) :: build_result()
  def token_mint(opts) do
    token = fetch!(opts, :token)
    metadata = Keyword.get(opts, :metadata, [])
    meta = Enum.map_join(metadata, "", &Proto.bytes_field(3, &1))

    inner =
      Proto.bytes_field(1, TokenId.to_proto(token)) <>
        maybe_varint(2, Keyword.get(opts, :amount, 0)) <> meta

    build(opts, @f_token_mint, inner)
  end

  @doc """
  Build + sign a `tokenBurn`. Required: `:token` and `:amount`. Requires the
  token's supply key to sign.
  """
  @spec token_burn(keyword()) :: build_result()
  def token_burn(opts) do
    token = fetch!(opts, :token)

    inner =
      Proto.bytes_field(1, TokenId.to_proto(token)) <>
        maybe_varint(2, Keyword.get(opts, :amount, 0))

    build(opts, @f_token_burn, inner)
  end

  @doc """
  Build + sign a `tokenAssociate`. Required: `:account` (an `AccountId`) and
  `:tokens` (a list of `TokenId`). The account being associated must sign — pass
  its key via `:signers` when it differs from the operator.
  """
  @spec token_associate(keyword()) :: build_result()
  def token_associate(opts) do
    account = fetch!(opts, :account)
    tokens = fetch!(opts, :tokens)
    token_fields = Enum.map_join(tokens, "", &Proto.bytes_field(2, TokenId.to_proto(&1)))

    inner = Proto.bytes_field(1, AccountId.to_proto(account)) <> token_fields
    build(opts, @f_token_associate, inner)
  end

  @doc "Build + sign a `tokenFreezeAccount`. Required: `:token`, `:account`. Needs the freeze key."
  @spec token_freeze(keyword()) :: build_result()
  def token_freeze(opts), do: build(opts, @f_token_freeze, token_account_body(opts))

  @doc "Build + sign a `tokenUnfreezeAccount`. Required: `:token`, `:account`. Needs the freeze key."
  @spec token_unfreeze(keyword()) :: build_result()
  def token_unfreeze(opts), do: build(opts, @f_token_unfreeze, token_account_body(opts))

  @doc "Build + sign a `tokenGrantKyc`. Required: `:token`, `:account`. Needs the KYC key."
  @spec token_grant_kyc(keyword()) :: build_result()
  def token_grant_kyc(opts), do: build(opts, @f_token_grant_kyc, token_account_body(opts))

  @doc "Build + sign a `tokenRevokeKyc`. Required: `:token`, `:account`. Needs the KYC key."
  @spec token_revoke_kyc(keyword()) :: build_result()
  def token_revoke_kyc(opts), do: build(opts, @f_token_revoke_kyc, token_account_body(opts))

  @doc """
  Build + sign a `tokenWipeAccount`. Required: `:token`, `:account`. For fungible
  tokens pass `:amount`; for NFTs pass `:serials` (a list of serial numbers).
  Needs the wipe key.
  """
  @spec token_wipe(keyword()) :: build_result()
  def token_wipe(opts) do
    serials = Keyword.get(opts, :serials, [])

    inner =
      Proto.bytes_field(1, TokenId.to_proto(fetch!(opts, :token))) <>
        Proto.bytes_field(2, AccountId.to_proto(fetch!(opts, :account))) <>
        maybe_varint(3, Keyword.get(opts, :amount, 0)) <>
        Enum.map_join(serials, "", &Proto.varint_field(4, &1))

    build(opts, @f_token_wipe, inner)
  end

  @doc "Build + sign a `tokenPause`. Required: `:token`. Needs the pause key."
  @spec token_pause(keyword()) :: build_result()
  def token_pause(opts), do: build(opts, @f_token_pause, token_body(opts))

  @doc "Build + sign a `tokenUnpause`. Required: `:token`. Needs the pause key."
  @spec token_unpause(keyword()) :: build_result()
  def token_unpause(opts), do: build(opts, @f_token_unpause, token_body(opts))

  # --- File Service -----------------------------------------------------------

  @doc """
  Build + sign a `fileCreate`. Opts: `:contents` (bytes), `:keys` (a list of
  `PublicKey`s controlling the file — defaults to the operator's key, making it
  mutable), `:expiration_seconds` (absolute unix seconds; default ~90 days out),
  `:file_memo`. The new file id is returned in the receipt.
  """
  @spec file_create(keyword()) :: build_result()
  def file_create(opts) do
    keys = opts[:keys] || [PrivateKey.public_key(fetch!(opts, :operator_key))]
    expiry = opts[:expiration_seconds] || unix_now() + @default_auto_renew_seconds

    inner =
      Proto.bytes_field(2, Timestamp.to_proto(%Timestamp{seconds: expiry, nanos: 0})) <>
        Proto.bytes_field(3, key_list(keys)) <>
        Proto.bytes_field(4, Keyword.get(opts, :contents, "")) <>
        maybe_string(8, opts[:file_memo])

    build(opts, @f_file_create, inner)
  end

  @doc "Build + sign a `fileAppend`. Required: `:file`, `:contents`. Needs the file's key(s)."
  @spec file_append(keyword()) :: build_result()
  def file_append(opts) do
    inner =
      Proto.bytes_field(2, FileId.to_proto(fetch!(opts, :file))) <>
        Proto.bytes_field(4, fetch!(opts, :contents))

    build(opts, @f_file_append, inner)
  end

  @doc """
  Build + sign a `fileUpdate`. Required: `:file`. Optional: `:contents`, `:keys`,
  `:expiration_seconds`. Needs the file's key(s).
  """
  @spec file_update(keyword()) :: build_result()
  def file_update(opts) do
    inner =
      Proto.bytes_field(1, FileId.to_proto(fetch!(opts, :file))) <>
        maybe_expiry(2, opts[:expiration_seconds]) <>
        maybe_key_list(3, opts[:keys]) <>
        maybe_string(4, opts[:contents])

    build(opts, @f_file_update, inner)
  end

  @doc "Build + sign a `fileDelete`. Required: `:file`. Needs the file's key(s)."
  @spec file_delete(keyword()) :: build_result()
  def file_delete(opts) do
    build(opts, @f_file_delete, Proto.bytes_field(2, FileId.to_proto(fetch!(opts, :file))))
  end

  # --- Schedule Service -------------------------------------------------------

  @doc """
  Build + sign a `scheduleCreate` wrapping an HBAR/token transfer. Transfer opts
  (`:transfers`, `:token_transfers`, `:nft_transfers`) describe the *scheduled*
  transaction. Optional: `:admin_key`, `:schedule_memo`. The scheduled transfer
  executes once it has collected all required signatures (from this create's
  signers and later `scheduleSign`s). Returns the schedule id in the receipt.
  """
  @spec schedule_create(keyword()) :: build_result()
  def schedule_create(opts) do
    # SchedulableTransactionBody { cryptoTransfer = 9 }
    schedulable = Proto.bytes_field(@f_schedulable_crypto_transfer, crypto_transfer_body(opts))

    inner =
      Proto.bytes_field(1, schedulable) <>
        maybe_string(2, opts[:schedule_memo]) <>
        maybe_key(3, opts[:admin_key])

    build(opts, @f_schedule_create, inner)
  end

  @doc "Build + sign a `scheduleSign`. Required: `:schedule_id`. Adds this tx's signers to the schedule."
  @spec schedule_sign(keyword()) :: build_result()
  def schedule_sign(opts) do
    build(opts, @f_schedule_sign, Proto.bytes_field(1, ScheduleId.to_proto(fetch!(opts, :schedule_id))))
  end

  # --- internals --------------------------------------------------------------

  # KeyList { repeated Key keys = 1 }
  defp key_list(keys), do: Enum.map_join(keys, "", &Proto.bytes_field(1, PublicKey.to_key_proto(&1)))

  defp maybe_key_list(_field, nil), do: <<>>
  defp maybe_key_list(field, keys), do: Proto.bytes_field(field, key_list(keys))

  defp maybe_expiry(_field, nil), do: <<>>
  defp maybe_expiry(field, seconds),
    do: Proto.bytes_field(field, Timestamp.to_proto(%Timestamp{seconds: seconds, nanos: 0}))

  defp unix_now, do: System.system_time(:second)

  # { token = 1 } — pause/unpause bodies.
  defp token_body(opts), do: Proto.bytes_field(1, TokenId.to_proto(fetch!(opts, :token)))

  # { token = 1, account = 2 } — freeze/unfreeze/grantKyc/revokeKyc bodies.
  defp token_account_body(opts) do
    Proto.bytes_field(1, TokenId.to_proto(fetch!(opts, :token))) <>
      Proto.bytes_field(2, AccountId.to_proto(fetch!(opts, :account)))
  end

  # repeated NftTransfer { sender = 1, receiver = 2, serialNumber = 3 } under
  # TokenTransferList.nftTransfers = 3.
  defp nft_transfer_list(moves) do
    Enum.map_join(moves, "", fn {%AccountId{} = sender, %AccountId{} = receiver, serial} ->
      nt =
        Proto.bytes_field(1, AccountId.to_proto(sender)) <>
          Proto.bytes_field(2, AccountId.to_proto(receiver)) <>
          Proto.varint_field(3, serial)

      Proto.bytes_field(3, nt)
    end)
  end

  # A run of repeated AccountAmount { accountID = 1, amount = 2 (sint64) } under
  # the given field number (1 for an HBAR TransferList, 2 for a TokenTransferList).
  defp account_amounts(moves, field) do
    Enum.map_join(moves, "", fn {%AccountId{} = account, amount} ->
      aa = Proto.bytes_field(1, AccountId.to_proto(account)) <> Proto.sint64_field(2, amount)
      Proto.bytes_field(field, aa)
    end)
  end

  defp maybe_varint(_field, 0), do: <<>>
  defp maybe_varint(field, value), do: Proto.varint_field(field, value)

  defp maybe_string(_field, nil), do: <<>>
  defp maybe_string(_field, ""), do: <<>>
  defp maybe_string(field, value), do: Proto.bytes_field(field, value)

  defp maybe_key(_field, nil), do: <<>>
  defp maybe_key(field, %PublicKey{} = key), do: Proto.bytes_field(field, PublicKey.to_key_proto(key))

  defp bool_int(true), do: 1
  defp bool_int(false), do: 0

  # TokenType enum
  defp token_type(:fungible), do: 0
  defp token_type(:nft), do: 1
  # TokenSupplyType enum
  defp supply_type(:infinite), do: 0
  defp supply_type(:finite), do: 1

  defp build(opts, data_field, data_bytes) do
    operator_id = fetch!(opts, :operator_id)
    operator_key = fetch!(opts, :operator_key)
    node = fetch!(opts, :node_account_id)
    tx_id = Keyword.get(opts, :transaction_id) || TransactionId.generate(operator_id)
    fee = Keyword.get(opts, :max_fee, @default_max_fee)
    # the operator (fee payer) always signs; :signers adds any extra required keys
    signers = [operator_key | Keyword.get(opts, :signers, [])]

    body =
      Proto.bytes_field(@f_transaction_id, TransactionId.to_proto(tx_id)) <>
        Proto.bytes_field(@f_node_account, AccountId.to_proto(node)) <>
        Proto.varint_field(@f_fee, fee) <>
        Proto.bytes_field(
          @f_valid_duration,
          Duration.to_proto(%Duration{seconds: @default_valid_seconds})
        ) <>
        Proto.maybe_bytes_field(@f_memo, opts[:memo]) <>
        Proto.bytes_field(data_field, data_bytes)

    %{transaction: sign_and_wrap(body, signers), transaction_id: tx_id}
  end

  defp sign_and_wrap(body_bytes, signers) when is_list(signers) do
    # SignatureMap { sigPair = 1 (repeated) } — one pair per distinct key.
    sig_map =
      signers
      |> Enum.uniq_by(fn key -> PublicKey.to_bytes(PrivateKey.public_key(key)) end)
      |> Enum.map_join("", fn %PrivateKey{} = key ->
        sig = PrivateKey.sign(key, body_bytes)
        Proto.bytes_field(1, signature_pair(PrivateKey.public_key(key), sig))
      end)

    # SignedTransaction { bodyBytes = 1, sigMap = 2 }
    signed = Proto.bytes_field(1, body_bytes) <> Proto.bytes_field(2, sig_map)
    # Transaction { signedTransactionBytes = 5 }
    Proto.bytes_field(5, signed)
  end

  # SignaturePair { pubKeyPrefix = 1, ed25519 = 3, ECDSASecp256k1 = 6 }
  defp signature_pair(%PublicKey{type: :ed25519} = pub, sig) do
    Proto.bytes_field(1, PublicKey.to_bytes(pub)) <> Proto.bytes_field(3, sig)
  end

  defp signature_pair(%PublicKey{type: :ecdsa_secp256k1} = pub, sig) do
    Proto.bytes_field(1, PublicKey.to_bytes(pub)) <> Proto.bytes_field(6, sig)
  end

  defp fetch!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "missing required option #{inspect(key)}"
    end
  end
end
