defmodule Hedera.TransactionId do
  @moduledoc """
  A Hedera transaction identifier: the paying `account_id` plus a
  `valid_start` timestamp. The valid-start must be slightly in the past when the
  transaction reaches the network, so `generate/1` backdates it a few seconds.
  """

  alias Hedera.{AccountId, Proto, Timestamp}

  @enforce_keys [:account_id, :valid_start]
  defstruct [:account_id, :valid_start]

  @type t :: %__MODULE__{account_id: AccountId.t(), valid_start: Timestamp.t()}

  @doc "Generate a transaction id for `account_id`, backdated by `back_seconds`."
  @spec generate(AccountId.t(), non_neg_integer()) :: t()
  def generate(%AccountId{} = account_id, back_seconds \\ 8) do
    seconds = System.os_time(:second) - back_seconds
    nanos = :rand.uniform(1_000_000_000) - 1
    %__MODULE__{account_id: account_id, valid_start: %Timestamp{seconds: seconds, nanos: nanos}}
  end

  @doc "Format as Hedera's `shard.realm.num@seconds.nanos`."
  @spec to_string(t()) :: binary()
  def to_string(%__MODULE__{account_id: a, valid_start: ts}) do
    "#{AccountId.to_string(a)}@#{Timestamp.to_string(ts)}"
  end

  @doc "Encode as a Hedera `TransactionID` protobuf (validStart = 1, accountID = 2)."
  @spec to_proto(t()) :: binary()
  def to_proto(%__MODULE__{account_id: a, valid_start: ts}) do
    Proto.bytes_field(1, Timestamp.to_proto(ts)) <> Proto.bytes_field(2, AccountId.to_proto(a))
  end
end
