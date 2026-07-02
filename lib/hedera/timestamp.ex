defmodule Hedera.Timestamp do
  @moduledoc "A Hedera consensus timestamp: whole `seconds` plus `nanos`."

  alias Hedera.Proto

  @enforce_keys [:seconds]
  defstruct [:seconds, nanos: 0]

  @type t :: %__MODULE__{seconds: integer(), nanos: non_neg_integer()}

  @doc ~S"""
  Format as Hedera's `seconds.nanos` (9-digit nanos).

  ## Examples

      iex> Hedera.Timestamp.to_string(%Hedera.Timestamp{seconds: 1_700_000_000, nanos: 42})
      "1700000000.000000042"
  """
  @spec to_string(t()) :: binary()
  def to_string(%__MODULE__{seconds: s, nanos: n}) do
    "#{s}.#{n |> Integer.to_string() |> String.pad_leading(9, "0")}"
  end

  @doc "Encode as a Hedera `Timestamp` protobuf message."
  @spec to_proto(t()) :: binary()
  def to_proto(%__MODULE__{seconds: s, nanos: n}) do
    Proto.varint_field(1, s) <> Proto.varint_field(2, n)
  end
end
