defmodule Hedera.Receipt do
  @moduledoc """
  A parsed Hedera `TransactionReceipt` — the consensus outcome of a transaction.
  For Consensus Service submits this carries the topic's new sequence number and
  running hash; for Token Service it carries the new `token_id` (on create) and
  the token's `new_total_supply` (on mint/burn).
  """

  alias Hedera.{Proto, TokenId, TopicId}

  # ResponseCodeEnum
  @status_unknown 21
  @status_success 22

  # TransactionReceipt field numbers
  @f_status 1
  @f_topic_id 6
  @f_topic_sequence_number 7
  @f_topic_running_hash 8
  @f_token_id 10
  @f_new_total_supply 11
  @f_serial_numbers 14

  @enforce_keys [:status]
  defstruct [
    :status,
    :topic_id,
    :topic_sequence_number,
    :topic_running_hash,
    :token_id,
    :new_total_supply,
    serial_numbers: []
  ]

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          topic_id: TopicId.t() | nil,
          topic_sequence_number: non_neg_integer() | nil,
          topic_running_hash: binary() | nil,
          token_id: TokenId.t() | nil,
          new_total_supply: non_neg_integer() | nil,
          serial_numbers: [integer()]
        }

  @doc "Has the receipt reached a final (non-UNKNOWN) status?"
  @spec final?(t()) :: boolean()
  def final?(%__MODULE__{status: status}), do: status != @status_unknown

  @doc "Did the transaction succeed (status SUCCESS)?"
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{status: status}), do: status == @status_success

  @doc "Parse a `TransactionReceipt` protobuf message."
  @spec parse(binary()) :: t()
  def parse(bytes) when is_binary(bytes) do
    fields = Proto.decode(bytes)

    %__MODULE__{
      status: Proto.field(fields, @f_status) || @status_unknown,
      topic_id: parse_topic_id(Proto.field(fields, @f_topic_id)),
      topic_sequence_number: Proto.field(fields, @f_topic_sequence_number),
      topic_running_hash: Proto.field(fields, @f_topic_running_hash),
      token_id: parse_token_id(Proto.field(fields, @f_token_id)),
      new_total_supply: Proto.field(fields, @f_new_total_supply),
      serial_numbers: parse_serials(fields)
    }
  end

  # `repeated int64 serialNumbers = 14` (NFT mint). Handle both proto3-packed
  # (one wire-2 field holding concatenated varints) and unpacked (many wire-0).
  defp parse_serials(fields) do
    Enum.flat_map(fields, fn
      {@f_serial_numbers, 0, v} -> [v]
      {@f_serial_numbers, 2, bin} -> Proto.decode_varints(bin)
      _ -> []
    end)
  end

  defp parse_topic_id(nil), do: nil

  defp parse_topic_id(bytes) do
    f = Proto.decode(bytes)

    %TopicId{
      shard: Proto.field(f, 1) || 0,
      realm: Proto.field(f, 2) || 0,
      num: Proto.field(f, 3) || 0
    }
  end

  defp parse_token_id(nil), do: nil

  defp parse_token_id(bytes) do
    f = Proto.decode(bytes)

    %TokenId{
      shard: Proto.field(f, 1) || 0,
      realm: Proto.field(f, 2) || 0,
      num: Proto.field(f, 3) || 0
    }
  end
end
