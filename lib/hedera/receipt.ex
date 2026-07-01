defmodule Hedera.Receipt do
  @moduledoc """
  A parsed Hedera `TransactionReceipt` — the consensus outcome of a transaction.
  For Consensus Service submits this carries the topic's new sequence number and
  running hash; for Token Service it carries the new `token_id` (on create) and
  the token's `new_total_supply` (on mint/burn).
  """

  alias Hedera.{ContractId, FileId, ScheduleId, TokenId, TopicId}

  # ResponseCodeEnum
  @status_unknown 21
  @status_success 22

  @enforce_keys [:status]
  defstruct [
    :status,
    :topic_id,
    :topic_sequence_number,
    :topic_running_hash,
    :token_id,
    :new_total_supply,
    :file_id,
    :schedule_id,
    :contract_id,
    serial_numbers: []
  ]

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          topic_id: TopicId.t() | nil,
          topic_sequence_number: non_neg_integer() | nil,
          topic_running_hash: binary() | nil,
          token_id: TokenId.t() | nil,
          new_total_supply: non_neg_integer() | nil,
          file_id: FileId.t() | nil,
          schedule_id: ScheduleId.t() | nil,
          contract_id: ContractId.t() | nil,
          serial_numbers: [integer()]
        }

  @doc "Has the receipt reached a final (non-UNKNOWN) status?"
  @spec final?(t()) :: boolean()
  def final?(%__MODULE__{status: status}), do: status != @status_unknown

  @doc "Did the transaction succeed (status SUCCESS)?"
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{status: status}), do: status == @status_success

  @doc "Parse a `TransactionReceipt` protobuf message (decoded by `Hedera.Pb`)."
  @spec parse(binary()) :: t()
  def parse(bytes) when is_binary(bytes) do
    pb = Hedera.Pb.TransactionReceipt.decode(bytes)

    %__MODULE__{
      status: pb.status,
      topic_id: from_id(pb.topicID, TopicId, :topicNum),
      topic_sequence_number: pb.topicSequenceNumber,
      topic_running_hash: pb.topicRunningHash,
      token_id: from_id(pb.tokenID, TokenId, :tokenNum),
      new_total_supply: pb.newTotalSupply,
      file_id: from_id(pb.fileID, FileId, :fileNum),
      schedule_id: from_id(pb.scheduleID, ScheduleId, :scheduleNum),
      contract_id: from_contract(pb.contractID),
      serial_numbers: pb.serialNumbers
    }
  end

  # Map a decoded Pb identifier (or nil) onto the SDK's shard/realm/num struct.
  defp from_id(nil, _mod, _num_key), do: nil

  defp from_id(pb, mod, num_key) do
    struct(mod, shard: pb.shardNum, realm: pb.realmNum, num: Map.get(pb, num_key))
  end

  # ContractID carries a `contract` oneof (contractNum | evm_address).
  defp from_contract(nil), do: nil

  defp from_contract(pb) do
    num = with {:contractNum, n} <- pb.contract, do: n, else: (_ -> nil)
    %ContractId{shard: pb.shardNum, realm: pb.realmNum, num: num}
  end
end
