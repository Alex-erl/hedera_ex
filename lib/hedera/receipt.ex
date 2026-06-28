defmodule Hedera.Receipt do
  @moduledoc """
  A parsed Hedera `TransactionReceipt` — the consensus outcome of a transaction.
  For Consensus Service submits this carries the topic's new sequence number and
  running hash.
  """

  alias Hedera.{Proto, TopicId}

  # ResponseCodeEnum
  @status_unknown 21
  @status_success 22

  # TransactionReceipt field numbers
  @f_status 1
  @f_topic_id 6
  @f_topic_sequence_number 7
  @f_topic_running_hash 8

  @enforce_keys [:status]
  defstruct [:status, :topic_id, :topic_sequence_number, :topic_running_hash]

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          topic_id: TopicId.t() | nil,
          topic_sequence_number: non_neg_integer() | nil,
          topic_running_hash: binary() | nil
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
      topic_running_hash: Proto.field(fields, @f_topic_running_hash)
    }
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
end
