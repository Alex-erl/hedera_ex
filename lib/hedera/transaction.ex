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
    Proto,
    PrivateKey,
    PublicKey,
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
  @f_crypto_transfer 14
  @f_consensus_create_topic 24
  @f_consensus_submit_message 27
  @f_token_creation 29
  @f_token_mint 37
  @f_token_burn 38
  @f_token_associate 40

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
    hbar = Keyword.get(opts, :transfers, [])
    token_transfers = Keyword.get(opts, :token_transfers, [])

    # CryptoTransferTransactionBody { TransferList transfers = 1 } — omitted when
    # there are no HBAR moves (proto3 leaves the empty message unset).
    hbar_field =
      case hbar do
        [] -> <<>>
        list -> Proto.bytes_field(1, account_amounts(list, 1))
      end

    # repeated TokenTransferList tokenTransfers = 2
    token_fields =
      Enum.map_join(token_transfers, "", fn {%TokenId{} = token, moves} ->
        # TokenTransferList { token = 1, repeated AccountAmount transfers = 2 }
        ttl = Proto.bytes_field(1, TokenId.to_proto(token)) <> account_amounts(moves, 2)
        Proto.bytes_field(2, ttl)
      end)

    build(opts, @f_crypto_transfer, hbar_field <> token_fields)
  end

  @doc """
  Build + sign a `tokenCreation`. Required: `:treasury` (an `AccountId`).
  Common opts: `:name`, `:symbol`, `:decimals`, `:initial_supply`, `:admin_key`,
  `:supply_key` (both `PublicKey`s — needed to later mint/burn), `:token_type`
  (`:fungible` | `:nft`), `:supply_type` (`:infinite` | `:finite`),
  `:max_supply`, `:token_memo`, `:auto_renew_account`, `:auto_renew_period`.

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
        maybe_key(10, opts[:supply_key]) <>
        maybe_varint(11, bool_int(Keyword.get(opts, :freeze_default, false))) <>
        Proto.bytes_field(14, AccountId.to_proto(auto_renew)) <>
        Proto.bytes_field(15, Duration.to_proto(%Duration{seconds: renew_period})) <>
        maybe_string(16, opts[:token_memo]) <>
        maybe_varint(17, token_type(Keyword.get(opts, :token_type, :fungible))) <>
        maybe_varint(18, supply_type(Keyword.get(opts, :supply_type, :infinite))) <>
        maybe_varint(19, Keyword.get(opts, :max_supply, 0))

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

  # --- internals --------------------------------------------------------------

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
