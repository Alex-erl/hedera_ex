defmodule Hedera.Transaction do
  @moduledoc """
  Builds and signs Hedera transactions, focused on the Consensus Service.

  The flow follows the Hedera HAPI: encode a `TransactionBody`, sign its exact
  bytes with the operator key, wrap them in a `SignedTransaction` (bodyBytes +
  signature map), and finally a `Transaction` (signedTransactionBytes). The
  signature is computed over the precise `bodyBytes` that are transmitted.

  Protobuf field numbers are taken from the canonical Hedera protobufs and are
  validated end-to-end against a live node by the gRPC layer.
  """

  alias Hedera.{AccountId, Duration, Proto, PrivateKey, PublicKey, TopicId, TransactionId}

  # default max fee: 2 ℏ in tinybars
  @default_max_fee 200_000_000
  @default_valid_seconds 120

  # TransactionBody field numbers
  @f_transaction_id 1
  @f_node_account 2
  @f_fee 3
  @f_valid_duration 4
  @f_memo 6
  # data oneof
  @f_consensus_create_topic 24
  @f_consensus_submit_message 27

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

  # --- internals --------------------------------------------------------------

  defp build(opts, data_field, data_bytes) do
    operator_id = fetch!(opts, :operator_id)
    operator_key = fetch!(opts, :operator_key)
    node = fetch!(opts, :node_account_id)
    tx_id = Keyword.get(opts, :transaction_id) || TransactionId.generate(operator_id)
    fee = Keyword.get(opts, :max_fee, @default_max_fee)

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

    %{transaction: sign_and_wrap(body, operator_key), transaction_id: tx_id}
  end

  defp sign_and_wrap(body_bytes, %PrivateKey{} = key) do
    signature = PrivateKey.sign(key, body_bytes)
    sig_pair = signature_pair(PrivateKey.public_key(key), signature)
    # SignatureMap { sigPair = 1 (repeated) }
    sig_map = Proto.bytes_field(1, sig_pair)
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
