defmodule Hedera.FileId do
  @moduledoc "A Hedera File Service file identifier `shard.realm.num`."

  alias Hedera.Proto

  @enforce_keys [:num]
  defstruct shard: 0, realm: 0, num: nil

  @type t :: %__MODULE__{shard: non_neg_integer(), realm: non_neg_integer(), num: non_neg_integer()}

  @doc "Parse `\"shard.realm.num\"`."
  @spec parse(binary()) :: t()
  def parse(string) when is_binary(string) do
    [shard, realm, num] = string |> String.split(".") |> Enum.map(&String.to_integer/1)
    %__MODULE__{shard: shard, realm: realm, num: num}
  end

  @doc "Format as `\"shard.realm.num\"`."
  @spec to_string(t()) :: binary()
  def to_string(%__MODULE__{shard: s, realm: r, num: n}), do: "#{s}.#{r}.#{n}"

  @doc "Encode as a Hedera `FileID` protobuf message."
  @spec to_proto(t()) :: binary()
  def to_proto(%__MODULE__{shard: s, realm: r, num: n}) do
    Proto.varint_field(1, s) <> Proto.varint_field(2, r) <> Proto.varint_field(3, n)
  end
end
